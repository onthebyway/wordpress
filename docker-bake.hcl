variable "IMAGE_NAME" {
  default = "ghcr.io/onthebyway/wordpress"
}

variable "WORDPRESS_SOURCE_IMAGE" {
  default = "wordpress:php8.4-fpm"
}

variable "UBUNTU_IMAGE" {
  default = "ubuntu:24.04"
}

variable "WP_CLI_IMAGE" {
  default = "wordpress:cli-2.12.0-php8.4"
}

variable "PHP_REDIS_VERSION" {
  default = "6.3.0"
}

variable "PHP_IMAGICK_VERSION" {
  default = "3.8.0"
}

group "default" {
  targets = ["php74", "php84"]
}

target "base" {
  context    = "."
  dockerfile = "Dockerfile"
  args = {
    WP_CLI_IMAGE        = "${WP_CLI_IMAGE}"
    PHP_REDIS_VERSION   = "${PHP_REDIS_VERSION}"
    PHP_IMAGICK_VERSION = "${PHP_IMAGICK_VERSION}"
  }
}

target "php74" {
  context    = "."
  dockerfile = "Dockerfile.php74"
  args = {
    UBUNTU_IMAGE          = "${UBUNTU_IMAGE}"
    WORDPRESS_SOURCE_IMAGE = "${WORDPRESS_SOURCE_IMAGE}"
    WP_CLI_IMAGE           = "${WP_CLI_IMAGE}"
  }
  tags = ["${IMAGE_NAME}:php7.4"]
}

target "php84" {
  inherits = ["base"]
  args = {
    WORDPRESS_IMAGE = "wordpress:php8.4-fpm"
  }
  tags = ["${IMAGE_NAME}:php8.4"]
}
