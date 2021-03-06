# Redirus worker [![build status](https://secure.travis-ci.org/dice-cyfronet/redirus-worker.png)](https://travis-ci.org/dice-cyfronet/redirus-worker) [![Code Climate](https://codeclimate.com/github/dice-cyfronet/redirus-worker.png)](https://codeclimate.com/github/dice-cyfronet/redirus-worker) [![Dependency Status](https://gemnasium.com/dice-cyfronet/redirus-worker.png)](https://gemnasium.com/dice-cyfronet/redirus-worker) [![Coverage Status](https://coveralls.io/repos/dice-cyfronet/redirus-worker/badge.png?branch=master)](https://coveralls.io/r/dice-cyfronet/redirus-worker)

Redirus worker is responsible for consuming create/delete subdomain redirection,
configuring appropriate nginx configuration and reloading nginx configurations.

## Requirements

**Project is designed for Linux operating system.**

- Linux (tested on Ubuntu)
- Nginx

## Nginx installation

Download and compile nginx:

```
mkdir /tmp/nginx && cd /tmp/nginx
curl http://nginx.org/download/nginx-1.7.4.tar.gz | tar xz
cd nginx-1.7.4
./configure --with-http_ssl_module --path=/nginx/installation/path
make
make install
```

Update nginx configuration:

```
edit /nginx/installation/path/conf/nginx.conf
```

the simplest configuration can looks as follow:

```
#user  nobody;
worker_processes  1;


#pid        logs/nginx.pid;
pid /nginx/installation/path/nginx.pid;

events {
    worker_connections  1024;
}


http {
    include       mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    #gzip  on;
    types_hash_max_size 2048;
    server_names_hash_bucket_size  128;

    include /path/to/generated/nginx/configurations/*;
}
```

If the nginx should bind into low-numbered port, e.g. port 80,
than following command need to be executed as root:

```
setcap 'cap_net_bind_service=+ep' /path/to/nginx/sbin/nginx
```

## Redirus worker installation

```bash
# Get code
git clone https://github.com/dice-cyfronet/redirus-worker.git

# Enter code dir
cd redirus-worker

# Install dependencies
gem install bundler
bundle install

# Copy configuration
cp config.yml.example config.yml

# Customise redis configuration and nginx config files locations
edit config.yml
```

## Example config.yml

```yaml
queues:
  - site_prefix
  - second_site_prefix

redis_url: redis://localhost:6379
namespace: redirus

nginx:
  configs_path: /path/to/dir/with/nginx/configs/
  pid: /path/to/nginx.pid
  http_template: |
    listen *:80;
  https_template: |
    listen *:443 ssl;
    ssl_certificate     /path/to/cert/dir/server.crt;
    ssl_certificate_key /path/to/cert/dir/server.key;
  config_template: |
    #{upstream}
    server {
      #{listen}
      server_name #{name}.my-domain.pl;
      server_tokens off;
      proxy_set_header X-Server-Address $scheme://#{name}.my-domain.pl;
      proxy_set_header Host $http_host;
      location / {
        proxy_pass http://#{upstream_name};
        #{properties}
      }
    }
  allowed_properties:
    - proxy_sent_timeout \d
    - proxy_read_timeout \d
```

Using `http_template`, `https_template`, `config_template` and
`allowed_properties` you can customize how nginx configuration for every
subdomain will looks like.

+ `http_template`  is used when http redirection is created
+ `https_template` is used when https redirection is created
+ `config_template` is used in both: when creating http and https redirection.
Inside this template in the `listen` variable section specifif for http or https
will be injected.
+ `allowed_properties` section is used to define allowed parameters which can be
passed used in generated configuration. Regular expressions can be used here.

E.g. when redirection with following parameters are requested:

```ruby
Sidekiq::Client.push(
  'queue' => 'cyfronet',
  'class' => Redirus::Worker::AddProxy,
  'args' => ['subdomain', ['127.0.0.1:80'], :http, ["proxy_send_timeout 6000"]])
```

than `/nginx/sites-enabled/subdomain_http` file with subdomain nginx
configuration is created:

```
upstream subdomain_http {
  server 127.0.0.1:80;
}
server {
  listen *:8000;
  server_name subdomain.localhost;
  server_tokens off;
  location / {
    proxy_pass http://subdomain_http;
    proxy_send_timeout 6000;
  }
}
```

## Run

```bash
/path/to/nginx/sbin/nginx
bundle exec ./bin/run
```
## Starting using upstart

At the beginning upstart need to be modified in order to allow normal user to use
upstart:

Replace `/etc/dbus-1/system.d/Upstart.conf` with content presented bellow
to allow any user to invoke all of upstarts methods:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<!DOCTYPE busconfig PUBLIC
  "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
  "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">

<busconfig>
  <!-- Only the root user can own the Upstart name -->
  <policy user="root">
    <allow own="com.ubuntu.Upstart" />
  </policy>

  <!-- Allow any user to invoke all of the methods on Upstart, its jobs
       or their instances, and to get and set properties - since Upstart
       isolates commands by user. -->
  <policy context="default">
    <allow send_destination="com.ubuntu.Upstart"
       send_interface="org.freedesktop.DBus.Introspectable" />
    <allow send_destination="com.ubuntu.Upstart"
       send_interface="org.freedesktop.DBus.Properties" />
    <allow send_destination="com.ubuntu.Upstart"
       send_interface="com.ubuntu.Upstart0_6" />
    <allow send_destination="com.ubuntu.Upstart"
       send_interface="com.ubuntu.Upstart0_6.Job" />
    <allow send_destination="com.ubuntu.Upstart"
       send_interface="com.ubuntu.Upstart0_6.Instance" />
  </policy>
</busconfig>
```

Add to `${HOME}/.bash_profile` (where `${HOME}` is the home directory of user used to run `upstart`):

```
if [ ! -f /var/run/user/$(id -u)/upstart/sessions/*.session ]
then
    /sbin/init --user --confdir ${HOME}/.init &
fi

if [ -f /var/run/user/$(id -u)/upstart/sessions/*.session ]
then
   export $(cat /var/run/user/$(id -u)/upstart/sessions/*.session)
fi
```

Next upstart configuration files need to be copied:

```
cd redirus-worker-directory
mkdir ${HOME}/.init

cp lib/support/upstart/redirus.conf ${HOME}/.init
cp lib/support/upstart/redirus-worker.conf ${HOME}/.init
cp lib/support/upstart/redirus-worker-1.conf ${HOME}/.init
cp lib/support/upstart/redirus-worker-nginx.conf ${HOME}/.init

# Change user name, path where redirus worker is installed and where
# location of nginx configurations directory to be created
editor ${HOME}/.init/redirus.conf

# Similar as above, plus if you are using ruby version manager uncomment and
# customize appropriate section for rbenv or rvm
editor ${HOME}/.init/redirus-worker-1.conf

# Update path to nginx
editor ${HOME}/.init/redirus-worker-nginx.conf
```
After loggin off and loggin on you should be able to start/stop/restart redirus
using following commands:

```
initctl start redirus
initctl stop redirus
initctl restart redirus
```

## Generating Add/Remove redirection requests

```ruby
# configure sidekiq client
Sidekiq.configure_client do |c|
  c.redis = { :namespace => Redirus::Worker.config.namespace, :url => Redirus::Worker.config.redis_url, queue: Redirus::Worker.config.queue }
end

# add new redirection
Sidekiq::Client.push('queue' => 'cyfronet', 'class' => Redirus::Worker::AddProxy, 'args' => ['subdomain', ['127.0.0.1'], :http, ["proxy_send_timeout 6000"]])

# remove redirection
Sidekiq::Client.push('queue' => 'cyfronet', 'class' => Redirus::Worker::RmProxy, 'args' => ['subdomain', :http])
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
