# Class: jbossMaster
#
# This module manages jbossMaster
#
# Parameters: none
#
# Actions:
#
# Requires: see Modulefile
#
# Sample Usage:
#
class odaijbossmaster (
  $package_url             = "http://",
  $bind_address            = $::ipaddress,
  $deploy_dir              = "/opt/jboss",
  $mode                    = "domain",
  $bind_address_management = $::ipaddress,
  $bind_address_unsecure   = $::ipaddress,
  # $domain_role             = 'master',
  $admin_user              = 'admin',
  $admin_user_password     = hiera('jbossadminpwd', ""),) {
  $appjboss = hiera('appjboss', undef)

  package { 'unzip': ensure => present, }

  class { 'opendai_java':
    distribution => 'jdk',
    version      => '6u25',
    repos        => $package_url,
  }

  class { 'jbossas':
    package_url             => "http://$package_url/",
    bind_address            => $bind_address,
    deploy_dir              => $deploy_dir,
    mode                    => $mode,
    version                 => 'EAP6.1.a',
    bind_address_management => $bind_address_management,
    bind_address_unsecure   => $bind_address_unsecure,
    domain_master_address   => $::ipaddress,
    role                    => 'master',
    admin_user              => $admin_user,
    admin_user_password     => $admin_user_password,
    require                 => [Class['opendai_java'], Package['unzip']],
    before                  => Anchor['odaijbossmaster:master_installed'],
  }

  jbossas::add_user { $admin_user:
    password => $admin_user_password,
    require  => [Class['jbossas']],
    before   => Anchor['odaijbossmaster:master_installed'],
  }

  # #@@odaijbossslave::setMaster{'setMasterIP':
  # #  ip_master => $::ipaddress,
  # #  tag      => $appjboss["tag"],
  # #  before     => Anchor['odaijbossmaster:master_installed'],
  # #}

  anchor { 'odaijbossmaster:master_installed': }

  # now wait for jboss to start
  # curl --digest -L -D - http://admin:opendaiadmin@10.1.1.77:9990/management --header "Content-Type: application/json" -d
  # '{"operation":"read-attribute","name":"release-codename","json.pretty":1}'

  exec { 'check_jboss_service_running':
    command   => "/usr/bin/curl --digest -L -D - http://${admin_user}:${admin_user_password}@${bind_address_management}:9990/management --header \"Content-Type: application/json\" -d '{\"operation\":\"read-attribute\",\"name\":\"release-codename\",\"json.pretty\":1}'",
    logoutput => true,
    tries     => 4,
    try_sleep => 30,
    require   => [Class['jbossas'], Anchor['odaijbossmaster:master_installed']],
  }

  # ########### Setting info for slaves
  # @@jbossas::set_domain_controller { 'jbslave':
  #   deploy_dir => "/opt/jboss",
  # #   deploy_dir => "/opt/jboss",
  #    require    => [Class['jbossas']],
  #    tag        => "domain_controller_jbslave"
  #  }

  Jbossas::Add_user <<| tag == $appjboss["user_tag"] |>>

  notice("now create server_groups")

  # need to add the server groups for application

  jbossas::add_server_group { 'app-server-group':
    profile              => "ha",
    socket_binding_group => "ha-sockets",
    offset               => "0",
    deploy_dir           => $deploy_dir,
    require              => [Exec['check_jboss_service_running']],
  }

  notice("now create jvm into server_groups")

  jbossas::add_jvm_server_group { 'app-server-group':
    heap_size     => "128m",
    max_heap_size => "1024m",
    deploy_dir    => $deploy_dir,
    require       => [Jbossas::Add_server_group['app-server-group']],
  }

  notice("now create server")

  #
  jbossas::add_server { 'app1':
    jbhost_name  => "master",
    autostart    => "true",
    server_group => "app-server-group",
    require      => [Jbossas::Add_jvm_server_group['app-server-group']],
  }

  jbossas::run_cli_command { 'set_app_multicast':
    command        => "/server-group=app-server-group/system-property=jboss.default.multicast.address:add(value=${appjboss["multicast_app"
        ]})",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"app-server-group\"},{\"system-property\":\"jboss.default.multicast.address\"}]",
    require        => [Jbossas::Add_jvm_server_group['app-server-group']]
  }

  jbossas::run_cli_command { 'set_app_lbgroup':
    command        => "/server-group=app-server-group/system-property=mycluster.modcluster.lbgroup:add(value=${appjboss["lbgroup_app"
        ]})",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"app-server-group\"},{\"system-property\":\"mycluster.modcluster.lbgroup\"}]",
    require        => [Jbossas::Add_jvm_server_group['app-server-group']]
  }

  jbossas::run_cli_command { 'set_app_balancer':
    command        => "/server-group=app-server-group/system-property=mycluster.modcluster.balancer:add(value=${appjboss["balancer"
        ]})",
    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"server-group\":\"app-server-group\"},{\"system-property\":\"mycluster.modcluster.balancer\"}]",
    require        => [Jbossas::Add_jvm_server_group['app-server-group']]
  }

  # Install MySQL, Postgresql and Oracle driver
  $mysql_file = 'mysql-connector-java-5.1.22-bin.jar'
  $file_url = "http://$package_url/"

  jbossas::add_jdbc_module { 'mysql':
    driver     => 'mysql-connector-java-5.1.22-bin.jar',
    driver_url => $file_url,
    profile    => 'ha',
    require    => [Class['jbossas'], Anchor['odaijbossmaster:master_installed']]
  }

  jbossas::add_jdbc_module { 'postgresql':
    driver     => 'postgresql-9.2-1002.jdbc4.jar',
    driver_url => $file_url,
    profile    => 'ha',
    require    => [Class['jbossas'], Anchor['odaijbossmaster:master_installed']]
  }

  jbossas::add_jdbc_module { 'oracle':
    driver     => 'ojdbc14.jar',
    driver_url => $file_url,
    profile    => 'ha',
    require    => [Class['jbossas'], Anchor['odaijbossmaster:master_installed']]
  }

  # mod_cluster stuff
  # set the name in the web subsystem so that the correct name is displayed in the proxy
  jbossas::run_cli_command { "set_ha_web_name":
    command => '/profile=ha/subsystem=web:write-attribute(name=instance-id,value="${jboss.node.name}")',
    require => Jbossas::Add_server['app1']
  }
  Jbossas::Set_mod_cluster <<| tag == $appjboss["mod_cluster_tag"] |>>

  # cleanup
  jbossas::run_cli_command { 'set_server_one_autostart':
    command => "/host=master/server-config=server-one:write-attribute(name=auto-start,value=false)",
    #    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\",
    #    \"address\":[{\"deployment\":\"${geoserver_file}\"}]",
    require => [Exec['check_jboss_service_running']],
  }

  jbossas::run_cli_command { 'set_server_two_autostart':
    command => "/host=master/server-config=server-two:write-attribute(name=auto-start,value=false)",
    #    unless_command => "\"operation\":\"read-resource\", \"include-runtime\":\"true\",
    #    \"address\":[{\"deployment\":\"${geoserver_file}\"}]",
    require => [Exec['check_jboss_service_running']],
  }

  # mount NFS
  $appdata = '/var/app_data'

  include nfs::client
  Nfs::Client::Mount <<| tag == 'nfs_app' |>> {
    ensure  => 'mounted',
    mount   => $appdata,
    options => 'rw,sync,hard,intr',
    before  => Anchor['odaijbossmaster:nfs'],
  }

  anchor { 'odaijbossmaster:nfs': }

  Jbossas::Run_cli_command <<| tag == $appjboss["server_slave_tag"] |>>

# Configure Zabbix for JBoss
  $cmd1 = "UserParameter=jboss.web[*], curl --digest -D - 'http://${admin_user}:${admin_user_password}@${::ipaddress}:9990/management/' -d '{\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"profile\":\"ha\"},{\"subsystem\":\"web\"},{\"connector\":\"http\"}], \"json.pretty\":1}' -HContent-Type:application/json -s| grep \$1|sed 's/\( \)*\"\$1\" : \([0-9]*\),/\2/'"
  notice("$cmd1")
  exec { 'zabbix-agentd-jboss_mon1':
    command => '/bin/echo "$cmd1" >> /etc/zabbix/zabbix_agentd.conf',
    require => File['/etc/zabbix/zabbix_agentd.conf'],
    unless  => '/bin/grep -q apache.status /etc/zabbix/zabbix_agentd.conf',
  }
  exec { 'zabbix-agent-jboss_mon1':
    command => '/bin/echo "$cmd1" >> /etc/zabbix/zabbix_agent.conf',
    require => File['/etc/zabbix/zabbix_agent.conf'],
    unless  => '/bin/grep -q apache /etc/zabbix/zabbix_agent.conf',
  }
                                                                                                                                                                                                        #/host=master/server=app1/deployment=opendaiexport.war/subsystem=web/servlet=opendaiexport:read-resource(include-runtime=true)
$cmd2 = "UserParameter=jboss.servlet[*], curl --digest -D - 'http://${admin_user}:${admin_user_password}@${::ipaddress}:9990/management/' -d '{\"operation\":\"read-resource\", \"include-runtime\":\"true\", \"address\":[{\"host\":\"\$1\"},{\"server\":\"\$2\"},{\"deployment\":\"\$3\"},{\"subsystem\":\"web\"},{\"servlet\":\"\$4\"}], \"json.pretty\":1}' -HContent-Type:application/json -s| grep \$5|sed 's/\( \)*\"\$5\" : \([0-9]*\),/\2/'"
  notice("$cmd2")
  exec { 'zabbix-agentd-jboss_mon2':
    command => '/bin/echo "$cmd2" >> /etc/zabbix/zabbix_agentd.conf',
    require => File['/etc/zabbix/zabbix_agentd.conf'],
    unless  => '/bin/grep -q apache.status /etc/zabbix/zabbix_agentd.conf',
  }
  exec { 'zabbix-agent-jboss_mon2':
    command => '/bin/echo "$cmd2" >> /etc/zabbix/zabbix_agent.conf',
    require => File['/etc/zabbix/zabbix_agent.conf'],
    unless  => '/bin/grep -q apache /etc/zabbix/zabbix_agent.conf',
  }


}