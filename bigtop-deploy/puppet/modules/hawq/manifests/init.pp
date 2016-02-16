# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

class hawq {
  class deploy ($roles) {
    if ("hawq" in $roles) {
      hawq::cluster_node { "hawq-node": }
    }
  }

  define cluster_node() {
    $hadoop_head_node = hiera("bigtop::hadoop_head_node")
    $hadoop_namenode_port = hiera("hadoop::common_hdfs::hadoop_namenode_port", "8020")
    $hawq_head = hiera("bigtop::hawq_master_node", "localhost")
    $hawq_head_port = hiera('bigtop::hawq_master_port', "5432")
    $hawq_yarn_rm_host = hiera('hadoop::common_yarn::hadoop_rm_host')
    $hawq_yarn_rm_port = hiera('hadoop::common_yarn::hadoop_rm_port')

    package { "hawq":
      ensure  => latest,
      require => Package["libhdfs3-devel"],
      ## require => for centos this crap needs epel-release
    }

    file { "/etc/default/hawq":
      content => template("hawq/hawq.default"),
      require => Package["hawq"],
    }

    file { "/etc/hawq/conf":
      ensure  => directory,
      owner   => 'hawq',
      group   => 'hawq',
      mode    => '0755',
      require => Package["hawq"],
    }
    file { "/etc/hawq/conf/hawq-site.xml":
        content => template('hawq/hawq-site.xml'),
        require => [File["/etc/hawq/conf"]],
        owner   => 'hawq',
        group   => 'hawq',
        mode    => '0755',
    }
    file { "/etc/hawq/conf/gpcheck.cnf":
        content => template('hawq/gpcheck.cnf'),
        require => [File["/etc/hawq/conf"]],
    }
    file { "/etc/hawq/conf/hdfs-client.xml":
        content => template('hawq/hdfs-client.xml'),
        require => [File["/etc/hawq/conf"]],
    }
    file { "/etc/hawq/conf/yarn-client.xml":
        content => template('hawq/yarn-client.xml'),
        require => [File["/etc/hawq/conf"]],
    }
    file { "/etc/hawq/conf/slaves":
        ensure  => file,
        content => "localhost", ## TODO - this has to be dynamic
    }

    exec { "install pygresql modules1":
      path 	 => ['/usr/bin'],
      command	 => 'pip --retries=50 --timeout=300 install pg8000 simplejson unittest2 pycrypto pygresql pyyaml lockfile paramiko psi',
      require	 => [ Package['python-pip', 'postgresql-devel'] ],
    }
    exec { "install pygresql modules2":
      path 	 => ['/usr/bin'],
      command	 => 'pip --retries=50 --timeout=300 install http://darcs.idyll.org/~t/projects/figleaf-0.6.1.tar.gz',
      require	 => [ Package['python-pip', 'pychecker'], Exec ['install pygresql modules1'] ],
      ## HAWQ install instructions are suggesting to
      ## uninstall postgresql postgresql-libs postgresql-devel at this point
      ## but I don't think it matter, and for sure looks ugly
    }

    package { "python-pip":
      ensure 	 => latest,
    }
    package { "pychecker":
      ensure 	 => latest,
    }
    package { "postgresql-devel":
      ensure 	 => latest,
    }
    package { "libhdfs3-devel":
      ensure     => latest,
    }

### TODO init require hdfs to be running. Need to test this
    exec { "hawk init master":
      path 	 => ['/usr/bin'],
      # Silly init will ask if I am really sure I want to init the cluster
      command	 => 'echo y | bash -x /usr/bin/hawq init master',
      require	 => [ Package['hawq'], Exec ['install pygresql modules2'] ],
    }

## TODO The expectation is that init will start the service. I don't think so...
    service { "hawq":
      ensure  => running,
      require => [ Package["hawq"], File["/etc/default/hawq"], Exec["hawk init"] ],
      subscribe => [ Package["hawq"], File["/etc/default/hawq", "/etc/hawq/conf/hawq-site.xml"] ]
    }
  }
}
