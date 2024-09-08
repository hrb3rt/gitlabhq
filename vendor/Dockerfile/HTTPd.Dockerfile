FROM httpd:2.4.62-alpine3.20

COPY ./ /usr/local/apache2/htdocs/
