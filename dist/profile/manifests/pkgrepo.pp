#
# Manage yum and apt repositories for Jenkins
class profile::pkgrepo (
  $docroot      = '/var/www/pkg.jenkins.io',
  $release_root = '/srv/releases/jenkins',
  $repo_fqdn    = 'pkg.jenkins.io',
  $mirror_fqdn  = 'mirrors.jenkins.io',
) {
  include ::stdlib
  include ::apache
  include ::apache::mod::rewrite

  validate_string($docroot)
  validate_string($release_root)

  include profile::apachemisc
  include profile::firewall
  include profile::letsencrypt

  $apache_log_dir = "/var/log/apache2/${repo_fqdn}"

  file { $apache_log_dir:
    ensure => directory,
  }

  file { $docroot:
    ensure  => directory,
    owner   => 'root',
    require => File[$apache_log_dir],
  }

  $repos = [
    "${docroot}/debian",
    "${docroot}/debian-rc",
    "${docroot}/debian-stable",
    "${docroot}/debian-stable-rc",
    "${docroot}/redhat",
    "${docroot}/redhat-rc",
    "${docroot}/redhat-stable",
    "${docroot}/redhat-stable-rc",
    "${docroot}/opensuse",
    "${docroot}/opensuse-rc",
    "${docroot}/opensuse-stable",
    "${docroot}/opensuse-stable-rc",
  ]

  file { $repos:
    ensure  => directory,
    require => File[$docroot],
  }

  file { suffix($repos, '/jenkins-ci.org.key'):
    ensure  => present,
    source  => "puppet:///modules/${module_name}/pkgrepo/jenkins-ci.org.key",
    require => File[$docroot],
  }

  profile::redhat_repo { ['redhat', 'redhat-stable', 'redhat-rc', 'redhat-stable-rc']:
    ensure    => present,
    docroot   => $docroot,
    repo_fqdn => $repo_fqdn,
    require   => File[$repos],
  }

  profile::debian_repo { ['debian', 'debian-stable', 'debian-rc', 'debian-stable-rc']:
    ensure      => present,
    docroot     => $docroot,
    direct_root => $release_root,
    mirror_fqdn => $mirror_fqdn,
    require     => File[$repos],
  }

  profile::opensuse_repo { ['opensuse', 'opensuse-stable', 'opensuse-rc', 'opensuse-stable-rc']:
    ensure      => present,
    docroot     => $docroot,
    mirror_fqdn => $mirror_fqdn,
    require     => File[$repos],
  }

  apache::vhost { $repo_fqdn:
    serveraliases   => [
      'pkg.jenkins-ci.org',
    ],
    port            => 443,
    # We need FollowSymLinks to ensure our fallback for old APT clients works
    # properly, see debian's htaccess file for more
    options         => 'Indexes FollowSymLinks MultiViews',
    override        => 'All',
    ssl             => true,
    ssl_key         => '/etc/letsencrypt/live/pkg.jenkins.io/privkey.pem',
    # When Apache is upgraded to >= 2.4.8 this should be changed to
    # fullchain.pem
    ssl_cert        => '/etc/letsencrypt/live/pkg.jenkins.io/cert.pem',
    ssl_chain       => '/etc/letsencrypt/live/pkg.jenkins.io/chain.pem',
    docroot         => $docroot,
    error_log_file  => "${repo_fqdn}/error.log",
    access_log_pipe => "|/usr/bin/rotatelogs ${apache_log_dir}/access.log.%Y%m%d%H%M%S 604800",
    require         => File[$docroot],
  }

  apache::vhost { "${repo_fqdn} unsecured":
    servername      => $repo_fqdn,
    port            => 80,
    docroot         => $docroot,
    redirect_status => 'permanent',
    redirect_dest   => "https://${repo_fqdn}/",
    error_log_file  => "${repo_fqdn}/error_nonssl.log",
    access_log_pipe => "|/usr/bin/rotatelogs ${apache_log_dir}/access_nonssl.log.%Y%m%d%H%M%S 604800",
    require         => Apache::Vhost[$repo_fqdn],
  }

  apache::vhost { 'pkg.jenkins-ci.org':
    port            => 80,
    docroot         => $docroot,
    override        => 'All',
    options         => 'Indexes FollowSymLinks MultiViews',
    error_log_file  => "${repo_fqdn}/legacy_nonssl.log",
    access_log_pipe => "|/usr/bin/rotatelogs ${apache_log_dir}/access_legacy_nonssl.log.%Y%m%d%H%M%S 604800",
    require         => Apache::Vhost[$repo_fqdn],
  }


  # We can only acquire certs in production due to the way the letsencrypt
  # challenge process works
  if (($::environment == 'production') and ($::vagrant != '1')) {
    letsencrypt::certonly { $repo_fqdn:
      domains     => [$repo_fqdn],
      plugin      => 'apache',
      manage_cron => true,
    }
  }
}
