# README #

This README should document the steps necessary to setup this project in order to run the "2epub-various" script.

### What is this repository for? ###

The "2epub-various" script, converted to use the Ruby language. It hopefully downloads the necessary chapters from dreamwidth.org appropriate to load the stories for [Effulgence](https://belltower.dreamwidth.org/8579.html) and [Incandescence](https://alicornutopia.dreamwidth.org/7441.html), as well as the [miscellaneous related sandboxes](https://alicornutopia.dreamwidth.org/1640.html), [glowfics](https://glowfic.dreamwidth.org/), [pixiethreads](https://pixiethreads.dreamwidth.org/613.html), [Marri's index](https://marrinikari.dreamwidth.org/1634.html), [radon-absinthe](https://radon-absinthe.dreamwidth.org/295.html), [the peterverse index](https://peterverse.dreamwidth.org/1643.html) and [Maggie's index](https://maggie-of-the-owls.dreamwidth.org/454.html) and then generates an epub for them.

### How do I get set up? ###
* Install [Ruby](https://www.ruby-lang.org/en/)
* Install [Nokogiri](http://www.nokogiri.org/tutorials/installing_nokogiri.html)
* (Use `bundler install` to do the above)
* Run do_various.rb and follow the instructions
* Use the generated .epub file on an ebook reader

### How do I fix issues with the sandbox? ###
If it's a "discretion advised" message, it's kinda stupid, but there is currently no proper way to have the script bypass it and load the pages anyway. Currently, it's a matter of performing the following steps:

* Run the TOC scraper for the applicable chapter collection
* Run the "flats parser" for the applicable chapter collection
* Open the applicable pages with the GET parameters `?(page=#&)style=site&view=flat` (in that order, thing in brackets when applicable, make # into numbers)
* Save the applicable pages as e.g. `web_cache/panfandom.dreamwidth.org/115923.html~×QMARK×~style=site&view=flat` (for http://panfandom.dreamwidth.org/115923.html?style=site&view=flat - make sure you replace the `?` to the `~×QMARK×~` (those aren't normal X's))
* Re-run the flats parser (it might complain about a 'Discretion Advised' message if you've done this before)
* Save the rest of the pages of the flat site (the page with the parameters `?page=1&style=site&view=flat` and then `?page=2&style=site&view=flat` (with `?` made into `~×QMARK×~` again... stupid Windows))
* (Optionally) make a backup of the files saved in the previous step (since they're so annoying to download one-by-one) (a backup as of 2015-12-24 can be found [here](https://www.dropbox.com/s/lpe84w73omv8gmh/backup-web_cache.zip?dl=0))
* Run the epub generation part of the code

This method is currently mostly tested, and should (hopefully) work. The stupid naming system (where `?` is instead `~×QMARK×~`) is to hopefully allow the thing to work on a Windows machine (since Windows disallows those characters in directories and file names)

### Who do I talk to? ###
If you have a problem, try contacting @Throne3d or another contributor to the project. Running this project is probably not for those without any programming or computing experience.
