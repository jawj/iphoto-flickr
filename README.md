flickrbackup
============

Ruby + Applescript to incrementally back up my iPhoto library to Flickr.

What it does
------------

Incrementally backs up the contents of an iPhoto library to Flickr. This is especially useful now that Flickr offer 1TB of free space.

More specifically, it:

* Uses AppleScript to get a list of all photos in the top-level Photos section of iPhoto (this excludes photos shared by others, iPhoto's Trash, and so on).
* Uploads to Flickr any of those photos it hasn't uploaded before.
* Uses AppleScript to get a list of all 'regular' albums (i.e. not smart albums or automatic ones, like Events or Faces).
* Creates a photoset on Flickr for any album it hasn't already done that for, adding all appropriate photos.
* Adds any photo in an album for which it's already created a photoset to that photoset if it hasn't already done so.

It makes no more than 1 request/second to the API, in line with Flickr's limit of 3600 requests/hour.

Strengths
---------

* It never deletes a photo or photoset, and it never alters a photo it's already uploaded. For a backup tool this is good: it means the backup can't be affected by loss or corruption of local photos.
* It's pretty careful not to mess its records up: it keeps append-only logs which are `fsync`ed after every write. So it ought to be safe to Ctrl-C it at any time.
* It works for me.

Limitations
-----------

* There's no restore feature to bring photos back from Flickr to iPhoto.
* The album/photoset feature is brittle: if you delete from Flickr any photo or photoset that this tool uploaded or created, this feature may subsequently fail. (The photo uploading feature is more robust: you can do what you like on Flickr and it won't care).
* It may not work for you.

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

http://opensource.org/licenses/MIT
