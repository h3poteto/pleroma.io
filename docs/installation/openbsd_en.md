# Installing on OpenBSD

{! backend/installation/otp_vs_from_source_source.include !}

This guide describes the installation and configuration of Pleroma (and the required software to run it) on a single OpenBSD 7.7 server.

For any additional information regarding commands and configuration files mentioned here, check the man pages [online](https://man.openbsd.org/) or directly on your server with the man command.

{! backend/installation/generic_dependencies.include !}

## Installation

### Preparing the system
#### Required software

To install required packages, run the following command:

```
# pkg_add elixir gmake git postgresql-server postgresql-contrib cmake libmagic libvips
```

Pleroma requires a reverse proxy, OpenBSD has relayd in base (and is used in this guide) and packages/ports are available for nginx (www/nginx) and apache (www/apache-httpd).
Independently of the reverse proxy, [acme-client(1)](https://man.openbsd.org/acme-client) can be used to get a certificate from Let's Encrypt.

#### Optional software

  * ImageMagick
  * ffmpeg
  * exiftool

To install the above:

```
# pkg_add ImageMagick ffmpeg p5-Image-ExifTool
```

For more information read [`docs/installation/optional/media_graphics_packages.md`](../installation/optional/media_graphics_packages.md):

### PostgreSQL

Switch to the \_postgresql user and initialize PostgreSQL:

```
# su _postgresql
$ initdb -D /var/postgresql/data -U postgres --encoding=utf-8 --lc-collate=C
```

Running PostgreSQL in a different directory than `/var/postgresql/data` requires changing the `daemon_flags` variable in the `/etc/rc.d/postgresql` script.

For security reasons it is recommended to change the authentication method for `local` and `host` connections with the localhost address to `scram-sha-256`.<br>
Do not forget to set a password for the `postgres` user before doing so, otherwise you won't be able to log back in unless you change the authentication method back to `trust`.<br>
Changing the password hashing algorithm is not needed.<br>
For more information [read](https://www.postgresql.org/docs/16/auth-pg-hba-conf.html) the PostgreSQL documentation.

Enable and start the postgresql service:

```
# rcctl enable postgresql
# rcctl start postgresql
```

To check that PostgreSQL started properly and didn't fail right after starting, run `# rcctl check postgresql` which should return `postgresql(ok)`.

### Configuring Pleroma

Pleroma will be run by a dedicated \_pleroma user. Before creating it, insert the following lines in `/etc/login.conf`:

```
pleroma:\
	:datasize=1536M:\
	:openfiles-max=4096:\
	:openfiles-cur=1024:\
	:setenv=LC_ALL=en_US.UTF-8,VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS,MIX_ENV=prod:\
	:tc=daemon:
```

This creates a "pleroma" login class and sets higher values than default for datasize and openfiles (see [login.conf(5)](https://man.openbsd.org/login.conf)), this is required to avoid having Pleroma crash some time after starting.

Create the \_pleroma user, assign it the pleroma login class and create its home directory (/home/\_pleroma/):

```
# useradd -m -L pleroma _pleroma
```

Switch to the _pleroma user:

```
# su -l _pleroma
```

Clone the Pleroma repository:

```
$ git clone -b stable https://git.pleroma.social/pleroma/pleroma.git
$ cd pleroma
```

Pleroma is now installed in /home/\_pleroma/pleroma/. To configure it run:

```
$ mix deps.get
$ MIX_ENV=prod mix pleroma.instance gen # You will be asked a few questions here.
$ cp config/generated_config.exs config/prod.secret.exs
```

Note: Answer yes when asked to install Hex and rebar3. This step might take some time as Pleroma gets compiled first.

Create the Pleroma database:

```
$ psql -U postgres -f config/setup_db.psql
```

Apply database migrations:

```
$ MIX_ENV=prod mix ecto.migrate
```

Note: You will need to run this step again when updating your instance to a newer version with `git pull` or `git checkout tags/NEW_VERSION`.

As \_pleroma in /home/\_pleroma/pleroma, you can now run `MIX_ENV=prod mix phx.server` to start your instance.
In another SSH session or a tmux window, check that it is working properly by running `ftp -MVo - http://127.0.0.1:4000/api/v1/instance`, you should get json output.
Double-check that the *uri* value near the bottom is your instance's domain name and the instance *title* are correct.

### Configuring acme-client

acme-client is used to get SSL/TLS certificates from Let's Encrypt.
Insert the following configuration in `/etc/acme-client.conf` and replace `example.tld` with your domain:

```
#
# $OpenBSD: acme-client.conf,v 1.5 2023/05/10 07:34:57 tb Exp $
#

authority letsencrypt {
        api url "https://acme-v02.api.letsencrypt.org/directory"
        account key "/etc/acme/letsencrypt-privkey.pem"
}

domain example.tld {
        # Adds alternative names to the certificate. Useful when serving media on another domain. Comma or space separated list.
        # alternative names {  }

        domain key "/etc/ssl/private/example.tld.key"
        domain certificate "/etc/ssl/example.tld_cert-only.crt"
        domain full chain certificate "/etc/ssl/example.tld.crt"
        sign with letsencrypt
}
```

Check the configuration:

```
# acme-client -n
```

### Configuring the Web server

Pleroma supports two Web servers:

  * nginx (recommended for most users)
  * OpenBSD's httpd and relayd (ONLY for advanced users, media proxy cache is NOT supported and will NOT work properly)

#### nginx

Since nginx is not installed by default, install it by running:

```
# pkg_add nginx
```

Add the following to `/etc/nginx/nginx.conf`, within the `server {}` block listening on port 80 and change `server_name`, as follows:

```
http {
    ...

    server {
        ...
        server_name localhost; # Replace with your domain

        location /.well-known/acme-challenge {
            rewrite ^/\.well-known/acme-challenge/(.*) /$1 break;
            root /var/www/acme;
        }
    }
}
```

Start the nginx service and acquire certificates:

```
# rcctl start nginx
# acme-client example.tld
```

Add certificate auto-renewal by adding acme-client to `/etc/weekly.local`, replace `example.tld` with your domain:

```
# echo "acme-client example.tld && rcctl reload nginx" >> /etc/weekly.local
```

OpenBSD's default nginx configuration does not contain an include directive, which is typically used for multiple sites.
Therefore, you will need to first create the required directory as follows:

```
# mkdir /etc/nginx/sites-available
# mkdir /etc/nginx/sites-enabled
```

Next add the `include` directive to `/etc/nginx/nginx.conf`, within the `http {}` block, as follows:

```
http {
    ...

    server {
        ...
    }

    include /etc/nginx/sites-enabled/*;
}
```

As root, copy `/home/_pleroma/pleroma/installation/pleroma.nginx` to `/etc/nginx/sites-available/pleroma.nginx`.

Edit default `/etc/nginx/sites-available/pleroma.nginx` settings and replace `example.tld` with your domain:

  * Uncomment the location block for `~ /\.well-known/acme-challenge` in the server block listening on port 80
    - add `rewrite ^/\.well-known/acme-challenge/(.*) /$1 break;` above the `root` location
    - change the `root` location to `/var/www/acme;`
  * Change `ssl_trusted_certificate` to `/etc/ssl/example.tld_cert-only.crt`
  * Change `ssl_certificate` to `/etc/ssl/example.tld.crt`
  * Change `ssl_certificate_key` to `/etc/ssl/private/example.tld.key`

Remove the following `location {}` block from `/etc/nginx/nginx.conf`, that was previously added for acquiring certificates and change `server_name` back to `localhost`:

```
http {
    ...

    server {
        ...
        server_name example.tld; # Change back to localhost

        # Delete this block
        location /.well-known/acme-challenge {
            rewrite ^/\.well-known/acme-challenge/(.*) /$1 break;
            root /var/www/acme;
        }
    }
}
```

Symlink the Pleroma configuration to the enabled sites:

```
# ln -s /etc/nginx/sites-available/pleroma.nginx /etc/nginx/sites-enabled
```

Check nginx configuration syntax by running:

```
# nginx -t
```

Note: If the above command complains about a `conflicting server name`, check again that the `location {}` block for acquiring certificates has been removed from `/etc/nginx/nginx.conf` and that the `server_name` has been reverted back to `localhost`.
After doing so run `# nginx -t` again.

If the configuration is correct, you can now enable and reload the nginx service:

```
# rcctl enable nginx
# rcctl reload nginx
```

#### httpd

***Skip this section when using nginx***

httpd will have two functions:

  * redirect requests trying to reach the instance over http to the https URL
  * get Let's Encrypt certificates, with acme-client

As root, copy `/home/_pleroma/pleroma/installation/openbsd/httpd.conf` to `/etc/httpd.conf`, or modify the existing one.

Edit `/etc/httpd.conf` settings and change:

  * `<ipaddr>` with your instance's IPv4 address
  * All occurrences of `example.tld` with your instance's domain name
  * When using IPv6 also change:
    - Uncomment the `ext_inet6="<ip6addr>"` line near the beginning of the file and change `<ip6addr` to your instance's IPv6 address
    - Uncomment the line starting with `listen on $ext_inet6` in the `server` block

Check the configuration by running:
```
# httpd -n
```

If the configuration is correct, enable and start the `httpd` service:

```
# rcctl enable httpd
# rcctl start httpd
```

Acquire certificate:

```
# acme-client example.tld
```

#### relayd

***Skip this section when using nginx***

relayd will be used as the reverse proxy sitting in front of pleroma.

As root, copy `/home/_pleroma/pleroma/installation/openbsd/relayd.conf` to `/etc/relayd.conf`, or modify the existing one.

Edit `/etc/relayd.conf` settings and change:

  * `<ipaddr>` with your instance's IPv4 address
  * All occurrences of `example.tld` with your instance's domain name
  * When using IPv6 also change:
    - Uncomment the `ext_inet6="<ip6addr>"` line near the beginning of the file and change `<ip6addr>` to your instance's IPv6 address
    - Uncomment the line starting with `listen on $ext_inet6` in the `relay wwwtls` block

Check the configuration by running:
```
# relayd -n
```

If the configuration is correct, enable and start the `relayd` service:

```
# rcctl enable relayd
# rcctl start relayd
```

Add certificate auto-renewal by adding acme-client to `/etc/weekly.local`, replace `example.tld` with your domain:

```
# echo "acme-client example.tld && rcctl reload relayd" >> /etc/weekly.local
```

#### (Strongly recommended) serve media on another domain

Refer to the [Hardening your instance](../configuration/hardening.md) document on how to serve media on another domain. We STRONGLY RECOMMEND you to do this to minimize attack vectors.

### Starting pleroma at boot

Copy the startup script and make sure it's executable:

```
# cp /home/_pleroma/pleroma/installation/openbsd/rc.d/pleroma /etc/rc.d/pleroma
# chmod 555 /etc/rc.d/pleroma
```

Enable and start the pleroma service:

```
# rcctl enable pleroma
# rcctl start pleroma
```

### Create administrative user

If your instance is up and running, you can create your first user with administrative rights with the following commands as the \_pleroma user:

```
$ cd pleroma
$ MIX_ENV=prod mix pleroma.user new <username> <your@emailaddress> --admin
```

### Further reading

{! backend/installation/further_reading.include !}

## Questions

Questions about the installation or didn’t it work as it should be, ask in [#pleroma:libera.chat](https://matrix.to/#/#pleroma:libera.chat) via Matrix or **#pleroma** on **libera.chat** via IRC.
