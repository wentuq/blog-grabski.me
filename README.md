

# Configuration of grabski.me


To run scripts properly, from main dir (blog-grabski.me) execute:
```
_tools/script.sh
```

## Run development locally


`be` is alias for `bundle exec`

Without ssl support:
```
be jekyll b && be jekyll s
```

To run locally with ssl support:
```
be jekyll b && be jekyll serve --ssl-cert _tools/server-keys/localhost.pem --ssl-key _tools/server-keys/localhost-key.pem --port 4000
```

## Local development Netlify CMS 
In main dir:
npx netlify-cms-proxy-server


CSP for working dev netlifycms in _config.yml
```
# Custom headers
webrick:
  headers:
    Content-Security-Policy: default-src 'self'; connect-src 'self' http://localhost:8081 ;img-src 'self' ; script-src 'self' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; font-src 'self' ; manifest-src 'self' ;
```

[![Build Status](https://travis-ci.org/wentuq/blog-grabski.me.svg?branch=master)](https://travis-ci.org/wentuq/blog-grabski.me)