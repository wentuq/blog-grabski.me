#! /bin/bash
# Run from main dir blog-grabski.me
# ./_scripts/script.sh

set -e

bundle exec ./_scripts/yaml.rb && JEKYLL_ENV=production bundle exec jekyll build