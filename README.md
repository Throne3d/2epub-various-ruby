# README #

This README should document the steps necessary to setup this project in order to run the "2epub-various" script.

### What is this repository for? ###

The "2epub-various" script, converted to use the Ruby language. It hopefully downloads the necessary chapters from dreamwidth.org appropriate to load the stories for [Effulgence](https://belltower.dreamwidth.org/8579.html) and [Incandescence](https://alicornutopia.dreamwidth.org/7441.html), as well as the [miscellaneous related sandboxes](https://alicornutopia.dreamwidth.org/1640.html), [glowfics](https://glowfic.dreamwidth.org/), [pixiethreads](https://pixiethreads.dreamwidth.org/613.html), [Marri's index](https://marrinikari.dreamwidth.org/1634.html), [Radon Absinthe](https://radon-absinthe.dreamwidth.org/295.html), [the Peterverse index](https://peterverse.dreamwidth.org/1643.html), [Maggie's index](https://maggie-of-the-owls.dreamwidth.org/454.html) and various other things, then generates an epub (or a 'report', or an HTML mirror, or outputs to a local Constellation Rails copy) for them.

### How do I get set up? ###
* Install [Ruby](https://www.ruby-lang.org/en/) – 2.3 *might* work, seems to work in at least one scenario, but has been reported to fail; 2.1 should work as a fallback.
* Install [Bundler](http://bundler.io/)
* Run `bundle` in the directory – this will use the `Gemfile` to fetch the appropriate dependencies
* Run `do_various.rb` as necessary – for example, to do an epub for Effulgence, run `do_various.rb epubdo_effulgence`, and to output the daily report, run `do_various.rb repdo_report`; if you're on Linux, to run these commands you want to open a terminal and write `./do_various.rb [thing]`, replacing `[thing]` as necessary.
* Use the generated .epub file on an ebook reader, or BB-code report in the daily reports thread, or some such.

### What can I do? ###
The different `process`es are outlined in `do_various.rb` in the code, and include: `do`, which downloads the data for a group, `epubdo`, which basically does `do` and then `output_epub`, and `repdo`, which basically does `do` and then `output_report`.

The different `group`s are outlined in `model_methods.rb`, in `FIC_NAME_MAPPING`. For example, `efful` maps to `effulgence`. The TOC pages are listed below in `FIC_TOCS`, and they are individually handled in `handlers_indexes.rb` depending on how the index is formatted.

Pass as a parameter, to `do_various.rb`, a `process` followed by a `group`, preferably separated by an underscore (`_`) but possibly works somehow else. For example, to do a report for the daily report (`repdo` as a process, `report` as a group), run `do_various.rb repdo_report` – in the Ubuntu Terminal, at least, you do this by navigating to this directory (`2epub-various-ruby`) and then executing the command `./do_various.rb repdo_report`.

### How do I fix issues with the sandbox? ###
There should no longer be any issues with the sandbox! The old issue, which was an inability to navigate around a "discretion advised" message, should now be fixed by using a thing called `Mechanize`.

### Who do I talk to? ###
If you have a problem, try contacting @Throne3d or another contributor to the project. Running this project is probably not for those without any programming or computing experience.
