#! /bin/bash
# Run from main dir blog-grabski.me
# ./_tools/script.sh

set -e

bundle exec ./_tools/yaml.rb && JEKYLL_ENV=production bundle exec jekyll build