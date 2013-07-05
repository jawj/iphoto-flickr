flickrbackup
============

Ruby + Applescript to incrementally back up my iPhoto library to Flickr.


What it does
------------

Incrementally backs up the contents of an iPhoto library to Flickr. This is especially useful now that Flickr offer 1TB of space for photos.

More specifically, it:

* Uses AppleScript to get a list of all photos in the top-level Photos section of iPhoto, and all 'regular' albums (i.e. not smart or automatic ones, like Events or Faces)
* Uploads to Flickr any photo it hasn't already done that to
* Creates a photoset on Flickr for any album it hasn't already done that for, adding all appropriate photos
* Adds any photo in an album for which it's already created a photoset to that photoset if it hasn't already done so

It never deletes a photo or photoset, and it never alters a photo it's already uploaded. For a backup tool this is good: it means the backup can't be affected by loss or corruption of local photos.

It's careful not to make more than 1 API request per second, since Flickr's limit is 3600/hour.

Limitations
-----------

* There's no restore feature to bring photos back from Flickr to iPhoto.
* The album/photoset feature is brittle: if you delete from Flickr any photos or photosets that this tool uploaded or created, you should expect the tool to subsequently fail. (The photo uploading feature is more robust: you can do what you like on Flickr and it won't care).

Installation
------------

1. Make sure you're a geek with a Mac
2. Request an API key + secret from Flickr
3. Install Ruby 1.9+ (unless you're on OS X 10.9+, which bundles it)
4. `gem install flickraw`
5. `git clone https://github.com/jawj/flickrbackup.git`
6. `chmod u+x flickrbackup.rb`

Usage
-----

`./flickrbackup.rb` and await further instructions.

Support and feature requests
----------------------------

I make no promises to enhance or support this script except in as far as it contributes to it backing up my own iPhoto library.

Licence
-------

MIT
