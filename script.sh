#! /bin/bash

set -e

bundle exec ./yaml.rb && JEKYLL_ENV=production bundle exec jekyll build