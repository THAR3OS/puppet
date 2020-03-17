# Class: clustercontrol
#
# This module manages clustercontrol
#
# @param is_controller
#   true for controller node, false for database node
# @param clustercontrol_host
#   host, where clustercontrol controller is installed
# @param ip_address
#   own ipaddress (defaults to $::ipaddress)
# @param api_token
#   apitoken created by
#   bash '/etc/puppet/modules/clustercontrol/files/s9s_helper.sh --generate-token'
# @param ssh_user
#   user used by the ssh command (defaults to root)
# @param ssh_port
#   port used by the ssh command (defaults to 22)
# @param ssh_key_type
#   type of key used by the ssh command (defaults to ssh-rsa)
# @param ssh_key
#   key used by the ssh command
# @param ssh_opts
#   opts for the ssh command
# @param sudo_password
#  if ssh user is not root and sudo should be used with a password
# @param mysql_server_addresses
#   address of an external mysql server if to be used for the cc database
# @param mysql_root_password
#   root password for mysql (defaults to 'password')
# @param mysql_cmon_root_password
#   cmon root password for mysql (defaults to 'password')
# @param mysql_cmon_password
#   cmon password for mysql (defaults to 'cmon')
# @param mysql_cmon_port
#   port for mysql (defaults to '3306')
# @param modulepath
#   path to the puppet module on the puppet server
#   (default: "${facts['puppet_environmentpath']}/${server_facts['environment']}/modules/clustercontrol/")
# @param datadir
#   directory for the database (default: /var/lib/mysql)
# @param use_repo
#   use severalnines repo (default: true)
# @param enabled
#    enable system services (default: true)
# @param http_ssl_cert_file
#   alternative ssl certificate file for webserver (default: undef, use shipped certificate)
# @param http_ssl_key_file
#   alternative ssl key file for webserver (default: undef, use shipped key)
#
class clustercontrol (
  $is_controller            = true,
  $clustercontrol_host      = '',
  $ip_address               = $::ipaddress,
  $api_token                = '',
  $ssh_user                 = 'root',
  $ssh_port                 = '22',
  $ssh_key_type             = 'ssh-rsa',
  $ssh_key                  = '',
  $ssh_opts                 = undef,
  $sudo_password            = undef,
  $mysql_server_addresses   = '',
  $mysql_root_password      = 'password',
  $mysql_cmon_root_password = 'password',
  $mysql_cmon_password      = 'cmon',
  $mysql_cmon_port          = '3306',
  $modulepath               = "${facts['puppet_environmentpath']}/${server_facts['environment']}/modules/clustercontrol",
  $datadir                  = '/var/lib/mysql',
  $use_repo                 = true,
  $enabled                  = true,
  $http_ssl_cert_file       = undef,
  $http_ssl_key_file        = undef,
) {

  if $enabled {
    $service_status = 'running'
  } else {
    $service_status = 'stopped'
  }

  if ($ssh_user == 'root') {
    $user_home            = '/root'
    $real_sudo_password   = undef
  } else {
    $user_home            = "/home/${ssh_user}"
    $rssh_opts             = '-nqtt'
    if ($sudo_password  != undef) {
      $real_sudo_password = "echo ${sudo_password} | sudo -S"
    } else {
      $real_sudo_password = 'sudo'
    }
  }

  if ($ssh_key == '') {
      $ssh_identity     = "${user_home}/.ssh/id_rsa_s9s"
      $ssh_identity_pub = "${user_home}/.ssh/id_rsa_s9s.pub"
  } else {
      $ssh_identity     = $ssh_key
      $ssh_identity_pub = "${ssh_key}.pub"
  }

  $backup_dir       = "${user_home}/backups"
  $staging_dir      = "${user_home}/s9s_tmp"

  Exec { path => ['/usr/bin','/bin','/usr/local/bin'] }

  if $is_controller {
    include clustercontrol::params

    service { $::clustercontrol::params::mysql_service:
      ensure     => running,
      enable     => true,
      hasrestart => true,
      hasstatus  => true,
      require    => [
        Package[$clustercontrol::params::mysql_packages],
        File[$datadir],
      ],
      notify     => Exec['create-root-password'],
      subscribe  => File[$clustercontrol::params::mysql_cnf],
    }

    package { $clustercontrol::params::mysql_packages :
      ensure => installed,
      notify => Exec['disable-extra-security'],
    }

    exec { 'create-root-password' :
      onlyif  => 'mysqladmin -u root status',
      command => "mysqladmin -u root password \"${mysql_cmon_root_password}\"",
      notify  => Exec[
        'grant-cmon-localhost',
        'grant-cmon-127.0.0.1',
        'grant-cmon-ip-address',
        'grant-cmon-fqdn'
      ]
    }

    file { '/root/.my.cnf':
      ensure  => 'file',
      owner   => 'root',
      group   => 'root',
      mode    => '0400',
      content => template('clustercontrol/_my.cnf.erb'),
    }

    file { $clustercontrol::params::mysql_cnf :
      ensure  => file,
      force   => true,
      content => template('clustercontrol/my.cnf.erb'),
      owner   => root,
      group   => root,
      mode    => '0644',
    }

    exec { 'grant-cmon-localhost':
      unless  => "mysqladmin -u cmon -p\"${mysql_cmon_password}\" -hlocalhost status",
      path    => $::path,
      command => "mysql -u root -p\"${mysql_cmon_root_password}\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@localhost IDENTIFIED BY \"${mysql_cmon_password}\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
    }

    exec { 'grant-cmon-127.0.0.1':
      unless  => "mysqladmin -u cmon -p\"${mysql_cmon_password}\" -h127.0.0.1 status",
      path    => $::path,
      command => "mysql -u root -p\"${mysql_cmon_root_password}\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@127.0.0.1 IDENTIFIED BY \"${mysql_cmon_password}\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
    }

    exec { 'grant-cmon-ip-address':
      unless  => "mysqladmin -u cmon -p\"${mysql_cmon_password}\" -h\"${::ip_address}\" status",
      path    => $::path,
      command => "mysql -u root -p\"${mysql_cmon_root_password}\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@\"${::ip_address}\" IDENTIFIED BY \"${mysql_cmon_password}\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
    }

    exec { 'grant-cmon-fqdn':
      unless  => "mysqladmin -u cmon -p\"${mysql_cmon_password}\" -h\"${::fqdn}\" status",
      path    => $::path,
      command => "mysql -u root -p\"${mysql_cmon_root_password}\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@\"${::fqdn}\" IDENTIFIED BY \"${mysql_cmon_password}\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
    }

    exec { 'create-cmon-db':
      unless  => "mysql -u root -p\"${mysql_cmon_root_password}\" -e 'QUIT' cmon",
      path    => $::path,
      command => "mysql -u root -p\"${mysql_cmon_root_password}\" -e 'CREATE SCHEMA IF NOT EXISTS cmon;'",
      notify  => Exec['import-cmon-db'],
    }

    exec { 'create-dcps-db':
      unless  => "mysql -u root -p\"${mysql_cmon_root_password}\" -e 'QUIT' dcps",
      path    => $::path,
      command => "mysql -u root -p\"${mysql_cmon_root_password}\" -e 'CREATE SCHEMA IF NOT EXISTS dcps;'",
      notify  => Exec['import-dcps-db'],
    }

    exec { 'import-cmon-db':
      onlyif  => [
        "test -f ${::clustercontrol::params::cmon_sql_path}/cmon_db.sql",
        "test -f ${::clustercontrol::params::cmon_sql_path}/cmon_data.sql",
      ],
      command => "mysql -f -u root -p\"${mysql_cmon_root_password}\" cmon < ${clustercontrol::params::cmon_sql_path}/cmon_db.sql && mysql -f -u root -p\"${mysql_cmon_root_password}\" cmon < ${clustercontrol::params::cmon_sql_path}/cmon_data.sql",
      notify  => Exec['configure-cmon-db'],
    }

    exec { 'configure-cmon-db':
      onlyif  => [
        "test -f ${clustercontrol::params::cmon_sql_path}/cmon_db.sql",
        "test -f ${clustercontrol::params::cmon_sql_path}/cmon_data.sql"
      ],
      command => "mysql -f -u root -p\"${mysql_cmon_root_password}\" cmon < /tmp/configure_cmon_db.sql",
      require => File['/tmp/configure_cmon_db.sql'],
    }

    file { '/tmp/configure_cmon_db.sql' :
      ensure  => present,
      content => template('clustercontrol/configure_cmon_db.sql.erb')
    }

    exec { 'import-dcps-db':
      onlyif  => "test -f ${::clustercontrol::params::wwwroot}/clustercontrol/sql/dc-schema.sql",
      command => "mysql -f -u root -p\"${mysql_cmon_root_password}\" dcps < ${::clustercontrol::params::wwwroot}/clustercontrol/sql/dc-schema.sql",
      notify  => Exec['create-dcps-api'],
    }

    exec { 'create-dcps-api':
      onlyif  => "mysql -u root -p\"${mysql_cmon_root_password}\" -e 'SHOW SCHEMAS LIKE \"dcps\";' 2>/dev/null",
      command => "mysql -u root -p\"${mysql_cmon_root_password}\" -e 'REPLACE INTO dcps.apis(id, company_id, user_id, url, token) VALUES (1, 1, 1, \"http://127.0.0.1/cmonapi\", \"${api_token}\");'",
    }

    file { $datadir :
      ensure  => directory,
      owner   => 'mysql',
      group   => 'mysql',
      require => Package[$::clustercontrol::params::mysql_packages],
      notify  => Service[$::clustercontrol::params::mysql_service],
    }

    file { $clustercontrol::params::cmon_conf :
      content => template('clustercontrol/cmon.cnf.erb'),
      owner   => 'root',
      group   => 'root',
      mode    => '0600',
      require => Package[$clustercontrol::params::cc_controller],
      notify  => [ Exec['create-cmon-db'], Service['cmon'] ],
    }

#   /*file { $clustercontrol::params::cert_file :
#     ensure => file
#   }

#   file { $clustercontrol::params::key_file :
#     ensure => file
#   }*/

    $http_ssl_cert_file_source = $http_ssl_cert_file ? {
      undef   => "${::clustercontrol::params::wwwroot}/clustercontrol/ssl/server.crt",
      default => $http_ssl_cert_file,
    }
    file { $::clustercontrol::params::cert_file:
      ensure  => 'present',
      source  => $http_ssl_cert_file_source,
      require => Package[$clustercontrol::params::cc_ui],
    }

    $http_ssl_key_file_source = $http_ssl_key_file ? {
      undef   => "${::clustercontrol::params::wwwroot}/clustercontrol/ssl/server.key",
      default => $http_ssl_key_file,
    }
    file { $::clustercontrol::params::key_file:
      ensure  => 'present',
      source  => $http_ssl_key_file_source,
      require => Package[$::clustercontrol::params::cc_ui],
    }

    package { $::clustercontrol::params::cc_controller:
      ensure  => 'installed',
      require => [
        $::clustercontrol::params::severalnines_repo,
        Package[$::clustercontrol::params::cc_dependencies],
      ],
    }

    $::clustercontrol::params::cc_dependencies.each | $package | {
      if !defined(Package[$package]) {
        package { $package:
          ensure => 'installed',
          notify => [
            Exec['allow-override-all'],
            File[$::clustercontrol::params::cert_file,$clustercontrol::params::key_file, $clustercontrol::params::apache_ssl_conf_file],
          ],
        }
      } else {
        Package <| title == $package |> {
          ensure => 'installed',
          notify => [
            Exec['allow-override-all'],
            File[$::clustercontrol::params::cert_file,$clustercontrol::params::key_file, $clustercontrol::params::apache_ssl_conf_file],
          ],
        }
      }
    }

    package { $::clustercontrol::params::cc_ui:
      ensure  => installed,
      require => Package[$::clustercontrol::params::cc_controller],
      notify  => Exec['create-dcps-db'],
    }

#   /*package { $clustercontrol::params::cc_cmonapi :
#     ensure => installed,
#     require => Package[[$clustercontrol::params::cc_controller, $clustercontrol::params::cc_ui]]
#   }*/

    service { $::clustercontrol::params::apache_service:
      ensure     => $service_status,
      enable     => $enabled,
      require    => Package[$::clustercontrol::params::cc_dependencies],
      hasrestart => true,
      hasstatus  => true,
      subscribe  => File[$::clustercontrol::params::apache_conf_file,$::clustercontrol::params::apache_ssl_conf_file],
    }

    ssh_authorized_key { $ssh_user:
      ensure => present,
      key    => generate('/bin/bash', "${modulepath}/files/s9s_helper.sh", '--read-key', $modulepath),
      name   => "${ssh_user}@clustercontrol",
      user   => $ssh_user,
      type   => 'ssh-rsa',
    }

#   /*
#   service { 'cmon' :
#     ensure  => $service_status,
#     enable  => $enabled,
#     require => Package[
#       $clustercontrol::params::cc_controller,
#       $clustercontrol::params::cc_ui
#     ],
#     subscribe    => File[$clustercontrol::params::cmon_conf],
#     hasrestart   => true,
#     hasstatus    => false
#   }*/

    file { [
        "${::clustercontrol::params::wwwroot}/cmon/",
        "${::clustercontrol::params::wwwroot}/cmon/upload",
        "${::clustercontrol::params::wwwroot}/cmon/upload/schema"
      ]:
      ensure  => 'directory',
      recurse => true,
      owner   => $::clustercontrol::params::apache_user,
      group   => $::clustercontrol::params::apache_user,
      require => [
        Package[$::clustercontrol::params::cc_ui],
        File[$ssh_identity, $ssh_identity_pub]
      ],
      notify  => Service['cmon'],
    }

    file { $ssh_identity:
      ensure => 'present',
      owner  => $ssh_user,
      group  => $ssh_user,
      mode   => '0600',
      source => 'puppet:///modules/clustercontrol/id_rsa_s9s',
    }

    file { $ssh_identity_pub:
      ensure => present,
      owner  => $ssh_user,
      group  => $ssh_user,
      mode   => '0644',
      source => 'puppet:///modules/clustercontrol/id_rsa_s9s.pub',
    }

    file { "${::clustercontrol::params::wwwroot}/clustercontrol/bootstrap.php":
      ensure  => 'present',
      replace => no,
      source  => "${::clustercontrol::params::wwwroot}/clustercontrol/bootstrap.php.default",
      require => Package[$::clustercontrol::params::cc_ui],
      notify  => [
        Exec['configure-cmonapi-bootstrap'],
        Exec['configure-cc-bootstrap']
      ],
    }

    file { "${::clustercontrol::params::wwwroot}/cmonapi/config/bootstrap.php":
      ensure  => 'present',
      replace => no,
      source  => "${::clustercontrol::params::wwwroot}/cmonapi/config/bootstrap.php.default",
      require => Package[$::clustercontrol::params::cc_ui],
      notify  => [
        Exec['configure-cmonapi-api-bootstrap'],
      ],
    }

    file { "${clustercontrol::params::wwwroot}/cmonapi/config/database.php":
      ensure  => present,
      content => template('clustercontrol/database.php.erb'),
      require => Package[$clustercontrol::params::cc_cmonapi]
    }

#
#   /*file { "${::clustercontrol::params::wwwroot}/clustercontrol/bootstrap.php":
#     ensure  => 'present',
#     replace => no,
#     source  => "${::clustercontrol::params::wwwroot}/clustercontrol/bootstrap.php.default",
#     require => Package[$::clustercontrol::params::cc_ui],
#     notify  => Exec['configure-cc-bootstrap'],
#   }

#   file { $::clustercontrol::params::cert_file:
#     ensure  => 'present',
#     source  => "${::clustercontrol::params::wwwroot}/cmonapi/ssl/server.crt",
#     require => Package[$::clustercontrol::params::cc_cmonapi],
#   }

#   file { $::clustercontrol::params::key_file:
#     ensure  => 'present',
#     source  => "${::clustercontrol::params::wwwroot}/cmonapi/ssl/server.key",
#     require => Package[$::clustercontrol::params::cc_cmonapi]
#   }*/

    exec { 'configure-cc-bootstrap':
      command => "sed -i 's|DBPASS|${mysql_cmon_password}|g' ${::clustercontrol::params::wwwroot}/clustercontrol/bootstrap.php && sed -i 's|DBPORT|${mysql_cmon_port}|g' ${::clustercontrol::params::wwwroot}/clustercontrol/bootstrap.php && sed -i \"s|//define('ENABLE_ONBOARDING_V1', 'true');|define('ENABLE_ONBOARDING_V1', 'false');|g\" ${::clustercontrol::params::wwwroot}/clustercontrol/bootstrap.php && sed -i \"s|//define('ENABLE_PRIVACY', true);|define('ENABLE_PRIVACY', true);|g\" ${::clustercontrol::params::wwwroot}/clustercontrol/bootstrap.php ",
      notify  => Service[$::clustercontrol::params::apache_service],
    }

    exec { 'configure-cmonapi-bootstrap':
      command => "sed -i 's|RPCTOKEN|${api_token}|g' ${::clustercontrol::params::wwwroot}/clustercontrol/bootstrap.php && sed -i 's|clustercontrol.severalnines.com|${::ip_address}\/clustercontrol|g' ${::clustercontrol::params::wwwroot}/clustercontrol/bootstrap.php",
    }

    exec { 'configure-cmonapi-api-bootstrap':
      command => "sed -i 's|GENERATED_CMON_TOKEN|${api_token}|g' ${::clustercontrol::params::wwwroot}/cmonapi/config/bootstrap.php && sed -i 's|clustercontrol.severalnines.com|${::ip_address}\/clustercontrol|g' ${::clustercontrol::params::wwwroot}/cmonapi/config/bootstrap.php",
    }

    exec { 'allow-override-all':
      unless  => "grep 'AllowOverride All' ${::clustercontrol::params::apache_conf_file}",
      command => "sed -i 's|AllowOverride None|AllowOverride All|g' ${::clustercontrol::params::apache_conf_file}",
    }

    service { 'cmon':
      ensure     => $service_status,
      enable     => $enabled,
      require    => Package[
        $::clustercontrol::params::cc_controller,
        $::clustercontrol::params::cc_ui,
        $::clustercontrol::params::cc_cloud,
        $::clustercontrol::params::cc_clud,
        $::clustercontrol::params::cc_notif,
        $::clustercontrol::params::cc_ssh
      ],
      subscribe  => File[$::clustercontrol::params::cmon_conf],
      hasrestart => true,
      hasstatus  => true,
    }

    service { 'cmon-cloud':
      ensure     => $service_status,
      enable     => $enabled,
      require    => Package[
        $::clustercontrol::params::cc_controller,
        $::clustercontrol::params::cc_ui,
        $::clustercontrol::params::cc_cloud,
        $::clustercontrol::params::cc_clud,
        $::clustercontrol::params::cc_notif,
        $::clustercontrol::params::cc_ssh
      ],
      subscribe  => File[$::clustercontrol::params::cmon_conf],
      hasrestart => true,
      hasstatus  => true,
    }

    service { 'cmon-events' :
      ensure     => $service_status,
      enable     => $enabled,
      require    => Package[
        $::clustercontrol::params::cc_controller,
        $::clustercontrol::params::cc_ui,
        $::clustercontrol::params::cc_cloud,
        $::clustercontrol::params::cc_clud,
        $::clustercontrol::params::cc_notif,
        $::clustercontrol::params::cc_ssh
      ],
      subscribe  => File[$::clustercontrol::params::cmon_conf],
      hasrestart => true,
      hasstatus  => true,
    }

    service { 'cmon-ssh':
      ensure     => $service_status,
      enable     => $enabled,
      require    => Package[
        $::clustercontrol::params::cc_controller,
        $::clustercontrol::params::cc_ui,
        $::clustercontrol::params::cc_cloud,
        $::clustercontrol::params::cc_clud,
        $::clustercontrol::params::cc_notif,
        $::clustercontrol::params::cc_ssh
      ],
      subscribe  => File[$::clustercontrol::params::cmon_conf],
      hasrestart => true,
      hasstatus  => true,
    }

  } else {

    ssh_authorized_key { '$ssh_user':
      ensure => 'present',
      key    => generate('/bin/bash', "${modulepath}/files/s9s_helper.sh", '--read-key', $modulepath),
      name   => "${ssh_user}@${clustercontrol_host}",
      user   => $ssh_user,
      type   => 'ssh-rsa',
      notify => [
        Exec['grant-cmon-controller'],
        Exec['grant-cmon-localhost'],
        Exec['grant-cmon-127.0.0.1'],
      ],
    }

    exec { 'grant-cmon-controller':
      onlyif  => 'which mysql',
      command => "mysql -u root -p\"${mysql_root_password}\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@\"${clustercontrol_host}\" IDENTIFIED BY \"${mysql_cmon_password}\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
    }

    exec { 'grant-cmon-localhost':
      onlyif  => 'which mysql',
      command => "mysql -u root -p\"${mysql_root_password}\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@localhost IDENTIFIED BY \"${mysql_cmon_password}\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
    }

    exec { 'grant-cmon-127.0.0.1':
      onlyif  => 'which mysql',
      command => "mysql -u root -p\"${mysql_root_password}\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@127.0.0.1 IDENTIFIED BY \"${mysql_cmon_password}\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
    }
  }
}
