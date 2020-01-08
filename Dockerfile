FROM php:7.4-fpm-alpine
LABEL Maintainer="Ocasta" \
      Description="Nginx PHP7 Wordpress Bedrock"


# Start with part of Wordpress' Alpine FPM Dockerfile https://github.com/docker-library/wordpress/blob/c63f536e5d24b474c93e6c4b8deeacf95a89eb64/php7.4/fpm-alpine/Dockerfile

# persistent dependencies
RUN apk add --no-cache \
# in theory, docker-entrypoint.sh is POSIX-compliant, but priority is a working, consistent image
    bash \
# BusyBox sed is not sufficient for some of our sed expressions
    sed \
# Ghostscript is required for rendering PDF previews
    ghostscript

# install the PHP extensions we need (https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions)
RUN set -ex; \
  \
  apk add --no-cache --virtual .build-deps \
    $PHPIZE_DEPS \
    freetype-dev \
    imagemagick-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    libzip-dev \
  ; \
  \
  docker-php-ext-configure gd --with-freetype --with-jpeg; \
  docker-php-ext-install -j "$(nproc)" \
    bcmath \
    exif \
    gd \
    mysqli \
    opcache \
    zip \
  ; \
  pecl install imagick-3.4.4; \
  pecl install ds-1.2.9; \
  pecl install apfd-1.0.1; \
  docker-php-ext-enable apfd ds imagick; \
  \
  runDeps="$( \
    scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
      | tr ',' '\n' \
      | sort -u \
      | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
  )"; \
  apk add --virtual .wordpress-phpexts-rundeps $runDeps; \
  apk del .build-deps

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
  } > /usr/local/etc/php/conf.d/opcache-recommended.ini
# https://wordpress.org/support/article/editing-wp-config-php/#configure-error-logging
RUN { \
# https://www.php.net/manual/en/errorfunc.constants.php
# https://github.com/docker-library/wordpress/issues/420#issuecomment-517839670
    echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
    echo 'error_reporting = 0'; \
    echo 'display_errors = Off'; \
    echo 'display_startup_errors = Off'; \
    echo 'log_errors = On'; \
    echo 'error_log = /dev/stderr'; \
    echo 'log_errors_max_len = 1024'; \
    echo 'ignore_repeated_errors = On'; \
    echo 'ignore_repeated_source = Off'; \
    echo 'html_errors = Off'; \
  } > /usr/local/etc/php/conf.d/error-logging.ini


# Add nginx, Wordpress, and our own configuration

# Install our additional packages
RUN apk --no-cache add ssmtp nginx supervisor composer

# Configure nginx
COPY config/nginx.conf /etc/nginx/conf.d/default.conf

# Configure PHP-FPM
# https://github.com/TrafeX/docker-php-nginx/blob/6a3b2f4abcd35da533ec191d8cb09eaa31159a85/config/fpm-pool.conf
COPY config/fpm-pool.conf /usr/local/etc/php-fpm.d/zzz_custom.conf
COPY config/php.ini /usr/local/etc/php/conf.d/custom.ini

# Configure supervisord
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Add Bedrock
RUN curl -L https://github.com/roots/bedrock/archive/0246c9c64bf8f2143e93b8a8f25d68fa787ea2ff.tar.gz | tar -xzv --strip=1 && \
    composer install --no-dev

RUN chown -R www-data.www-data /var/www/html/web/app/uploads/

# Expose the nginx port
EXPOSE 80

COPY ./scripts/. /usr/local/bin/
ENTRYPOINT ["docker-entrypoint"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
