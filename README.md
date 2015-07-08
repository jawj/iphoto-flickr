iPhoto -> Flickr
================

Ruby + Applescript to incrementally back up my iPhoto library to Flickr.

What it does
------------

Incrementally backs up the contents of an iPhoto library to Flickr. This is especially useful now that Flickr offer 1TB of free space.

More specifically, it:

* Uses AppleScript to get a list of all photos in the top-level Photos section of iPhoto (this excludes photos shared by others, iPhoto's Trash, and so on).
* Uploads to Flickr any of those photos it hasn't uploaded before.
* Uses AppleScript to get a list of all 'regular' iPhoto albums (i.e. not smart albums or automatic ones, like Events or Faces).
* Creates a photoset on Flickr for any iPhoto album it hasn't already done that for.
* Adds any photo in an iPhoto album to the corresponding Flickr photoset if it hasn't already done so.

It makes no more than 1 request/second to the API, in line with Flickr's limit of 3600 requests/hour.

Hats off to the [flickraw gem](https://github.com/hanklords/flickraw) for doing all the Flickr donkey work.

Strengths
---------

* It never deletes a photo or photoset, and it never alters a photo it's already uploaded. For a backup tool this is good: it means the backup can't be affected by loss or corruption of local photos.
* It's pretty careful not to mess its records up: it keeps append-only logs which are `fsync`ed after every write. So it ought to be safe to Ctrl-C it at any time.

Limitations
-----------

* There's no restore feature to bring photos back from Flickr to iPhoto.
* Error-handling is minimal: various error conditions (such as no Internet connectivity) will give you a stack trace.

Installation
------------

1. Make sure you're a geek with a Mac
2. Request an API key + secret from Flickr
3. Install Ruby 1.9+ (unless you're on OS X 10.9+, which apparently bundles Ruby 2)
4. `gem install flickraw-cached colorize`
5. `git clone https://github.com/jawj/flickrbackup.git`
6. `chmod u+x flickrbackup.rb`

Usage
-----

`./flickrbackup.rb` and await further instructions.

On first run you'll be prompted to authenticate with Flickr before backup proceeds. Your OAuth credentials are stored, so on subsequent runs you'll just see something like the following:

<pre>Georges-MBP:flickrbackup George$ ./flickrbackup.rb
Authenticated as: george

9025 photos in iPhoto library
4 photos not yet uploaded to Flickr
1. Uploading '/Users/George/Pictures/iPhoto Library/Previews/2013/07/08/20130708-215354/F6hf3i9DTFq0dXcULUNiQQ/IMG_2948.JPG' ... 4294991038 -> 9264815520
2. Uploading '/Users/George/Pictures/iPhoto Library/Previews/2013/07/08/20130708-215354/p6NrRDroSci6hFvRgyi67A/IMG_2949.JPG' ... 4294991036 -> 9264816628
3. Uploading '/Users/George/Pictures/iPhoto Library/Masters/2013/07/08/20130708-215318/IMG_0018.PNG' ... 4294991024 -> 9264817274
4. Uploading '/Users/George/Pictures/iPhoto Library/Previews/2013/07/09/20130709-205846/xpgCtTqTQ+CkFbO0%5PrVA/IMG_2954.jpg' ... 4294991052 -> 9264818976

65 standard albums in iPhoto
Adding photo 4294991034 -> 9264801368 to photoset 4294976678 -> 72157634473345113 ... done
Adding photo 4294991038 -> 9264815520 to photoset 4294976678 -> 72157634473345113 ... done
Adding photo 4294991036 -> 9264816628 to photoset 4294976678 -> 72157634473345113 ... done
Creating new photoset: 'Test album Thursday' ... 4294977929 -> 72157634599278172
Adding photo 4294990998 -> 9230172174 to photoset 4294977929 -> 72157634599278172 ... done
Adding photo 4294991034 -> 9264801368 to photoset 4294977929 -> 72157634599278172 ... done
Adding photo 4294991038 -> 9264815520 to photoset 4294977929 -> 72157634599278172 ... done
Adding photo 4294991036 -> 9264816628 to photoset 4294977929 -> 72157634599278172 ... done</pre>

Arrows represent mappings from iPhoto object IDs to Flickr object IDs. All records are stored in `~/Library/Application Support/flickrbackup`.

Support and feature requests
----------------------------

I make no promises to enhance or support this script except in as far as it contributes to it backing up my own iPhoto library.

Licence
-------

http://opensource.org/licenses/GPL-3.0
