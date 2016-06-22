#!/bin/bash

rm -rf public \
&& mkdir public \
&& ./node_modules/.bin/vulcanize --strip-comments --inline-css --inline-scripts src/index.html > public/index.html \
&& cp src/favicon.ico public/ \
&& cp -r src/fonts public/ 
echo "./public/index.html is ready"
