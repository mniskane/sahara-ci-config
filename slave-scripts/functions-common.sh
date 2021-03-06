#!/bin/bash -xe

configs_path=$WORKSPACE/sahara-ci-config/config
template_vars_file=/tmp/template_vars.ini

eval ci_flavor_id="\'20\'"
eval medium_flavor_id="\'3\'"
eval large_flavor_id="\'4\'"

check_dependency_patch() {
  local project_name=$1
  local zuul_changes=${ZUUL_CHANGES:-$2}
  for dep in $(echo "$zuul_changes" | tr "^" "\n"); do
     cur_proj=$(echo $dep|awk -F: '{print $1}')
     [[ "$cur_proj" =~ ^"$project_name"$ ]] && return 0
  done
  return 1
}

conf_has_option() {
  local file=$1
  local section=$2
  local option=$3
  local line

  line=$(sed -ne "/^\[$section\]/,/^\[.*\]/ { /^$option[ \t]*=/ p; }" "$file")
  [ -n "$line" ]
}

enable_pypi() {
  mkdir -p ~/.pip
  export PIP_USE_MIRRORS=True
  cp $configs_path/pip.conf ~/.pip/pip.conf
}

failure() {
  local reason=$1
  print_python_env
  echo "$reason"
  exit 1
}

get_dependency() {
  local project_dir=$1
  local project_name=$2
  local branch=$3
  if check_dependency_patch "$project_name"
  then
    # when patch depends on patch to some project
    pushd "$(pwd)"
    mkdir "$project_dir" && cd "$project_dir"
    ZUUL_PROJECT="$project_name" /usr/local/jenkins/slave_scripts/gerrit-git-prep.sh https://review.openstack.org https://review.openstack.org
    popd
  else
    git clone https://review.openstack.org/"$project_name" "$project_dir" -b "$branch"
  fi
}

insert_config_value() {
  local file=$1
  local section=$2
  local option=$3
  local value=$4

  [[ -z $section || -z $option ]] && return

  if ! grep -q "^\[$section\]" "$file" 2>/dev/null; then
      # Add section at the end
      echo -e "\n[$section]" >>"$file"
  fi
  if ! conf_has_option "$file" "$section" "$option"; then
      # Add it
      sed -i -e "/^\[$section\]/ a\\
$option = $value
" "$file"
  else
      local sep
      sep=$(echo -ne "\x01")
      # Replace it
      sed -i -e '/^\['${section}'\]/,/^\[.*\]/ s'${sep}'^\('${option}'[ \t]*=[ \t]*\).*$'${sep}'\1'"${value}"${sep} "$file"
  fi
}

print_python_env() {
  [ -f $SAHARA_PATH/.tox/integration/bin/pip ] && $SAHARA_PATH/.tox/integration/bin/pip freeze > $WORKSPACE/logs/python-integration-env.txt
  [ -f $SAHARA_PATH/.tox/scenario/bin/pip ] && $SAHARA_PATH/.tox/scenario/bin/pip freeze > $WORKSPACE/logs/python-scenario-env.txt
  pip freeze > $WORKSPACE/logs/python-system-env.txt
}

run_tests() {
  local scenario_config=$1
  # shellcheck disable=SC2034
  local concurrency=${2:-"1"}
  echo "Integration tests are started"
  export PYTHONUNBUFFERED=1
  local scenario_edp
  scenario_edp="${tests_etc:?}/edp.yaml.mako"
  if [ ! -f $scenario_edp ]; then
    scenario_edp="${tests_etc:?}/edp.yaml"
  fi
  # Temporary use additional log file, due to wrong status code from tox scenario tests
  pushd $SAHARA_TESTS_PATH
  # tox -e scenario -- --verbose -V $template_vars_file $scenario_credentials $scenario_edp $scenario_config || failure "Integration tests are failed"
  tox -e venv -- sahara-scenario --verbose -V $template_vars_file $scenario_edp $scenario_config | tee tox.log
  STATUS=$(grep "\ -\ Failed" tox.log | awk '{print $3}')
  if [ "$STATUS" != "0" ]; then failure "Integration tests have failed"; fi
  popd
}

scenario_has_option() {
  local file=$1
  local main_key=$2
  local stop_key=$3
  local sub_key=$4
  local line

  line=$(sed -ne "/$main_key\:/,/$stop_key/ { /[ \t]$sub_key:/ p; }" "$file")
  [ -n "$line" ]
}

start_sahara() {
  local conf_path=$1
  local conf_dir
  conf_dir=$(dirname $1)
  local mode=${2:-"distribute"}
  mkdir $WORKSPACE/logs
  sahara-db-manage --config-file $conf_path  upgrade head || failure "Command 'sahara-db-manage' failed"
  if [ "$mode" == "distribute" ]; then
    screen -dmS sahara-api /bin/bash -c "PYTHONUNBUFFERED=1 sahara-api --config-dir $conf_dir -d --log-file $WORKSPACE/logs/sahara-log-api.txt"
    sleep 2
    screen -dmS sahara-engine_1 /bin/bash -c "PYTHONUNBUFFERED=1 sahara-engine --config-dir $conf_dir -d --log-file $WORKSPACE/logs/sahara-log-engine-1.txt"
    screen -dmS sahara-engine_2 /bin/bash -c "PYTHONUNBUFFERED=1 sahara-engine --config-dir $conf_dir -d --log-file $WORKSPACE/logs/sahara-log-engine-2.txt"
  else
    screen -dmS sahara-all /bin/bash -c "PYTHONUNBUFFERED=1 sahara-all --config-dir $conf_dir -d --log-file $WORKSPACE/logs/sahara-log.txt"
  fi

  api_responding_timeout=30
  if ! timeout ${api_responding_timeout} sh -c "while ! curl -s http://127.0.0.1:8386/v1.1/ 2>/dev/null | grep -q 'requires authentication\|Authentication required' ; do sleep 1; done"; then
    failure "Sahara API failed to respond within ${api_responding_timeout} seconds"
  fi
}

write_sahara_main_conf() {
  local conf_path=$1
  local plugin=$2
  insert_config_value $conf_path DEFAULT infrastructure_engine heat
  insert_config_value $conf_path DEFAULT api_workers 4
  insert_config_value $conf_path DEFAULT use_identity_api_v3 true
  insert_config_value $conf_path DEFAULT use_neutron true
  insert_config_value $conf_path DEFAULT min_transient_cluster_active_time 30
  insert_config_value $conf_path DEFAULT node_domain ci
  insert_config_value $conf_path DEFAULT plugins $plugin
  insert_config_value $conf_path database connection mysql+pymysql://sahara-citest:sahara-citest@localhost/sahara?charset=utf8
  insert_config_value $conf_path keystone_authtoken auth_uri http://$OPENSTACK_HOST:5000/v2.0/
  insert_config_value $conf_path keystone_authtoken identity_uri http://$OPENSTACK_HOST:35357/
  insert_config_value $conf_path keystone_authtoken admin_user $OS_USERNAME
  insert_config_value $conf_path keystone_authtoken admin_password $OS_PASSWORD
  insert_config_value $conf_path keystone_authtoken admin_tenant_name $OS_TENANT_NAME
  insert_config_value $conf_path keystone_authtoken admin_tenant_name $OS_TENANT_NAME
  insert_config_value $conf_path glance endpoint_type publicURL
  insert_config_value $conf_path cinder endpoint_type publicURL
  insert_config_value $conf_path heat endpoint_type publicURL
  insert_config_value $conf_path keystone endpoint_type publicURL
  insert_config_value $conf_path swift endpoint_type publicURL
  insert_config_value $conf_path neutron endpoint_type publicURL
  insert_config_value $conf_path nova endpoint_type publicURL

  echo "----------- sahara.conf -----------"
  cat $conf_path
  echo "--------------- end ---------------"
}

write_tests_conf() {
  local cluster_name=$1
  local image_name=$2
  local scenario=$3
  local image_variable_name
  image_variable_name=$(grep image "${scenario}" | awk '{ print $2 }' | sed "s/[{}$]//g")
  export NETWORK="neutron"
echo "[DEFAULT]
$image_variable_name: $image_name
cluster_name: $cluster_name
ci_flavor_id: ${ci_flavor_id:?}
medium_flavor_id: ${medium_flavor_id:?}
large_flavor_id: ${large_flavor_id:?}
" | tee ${template_vars_file}
}

get_template_path() {
  local branch=$1
  local plugin=$2
  local base_path=$3

  if [[ $branch == *"stable"* ]]; then
      local release
      release=${branch//stable\//}
      base_path="$base_path/$release"
  fi
  local suffix
  suffix=${plugin//_/-}
  echo "$base_path/$suffix.yaml.mako"
}

