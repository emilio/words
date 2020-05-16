.PHONY: build
build:
	bundle exec jekyll build --incremental

.PHONY: deploy
deploy: build
	scp -r _site/* root@emiliocobos.net:/var/www/vhosts/crisal.io/words
	scp .htaccess root@emiliocobos.net:/var/www/vhosts/crisal.io/words

.PHONY: serve
serve: build
	bundle exec jekyll serve
