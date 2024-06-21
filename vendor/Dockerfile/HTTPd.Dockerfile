FROM httpd:2.4.59-alpine3.20

COPY ./ /usr/local/apache2/htdocs/
