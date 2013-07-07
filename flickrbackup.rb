#!/usr/bin/env ruby
# encoding: utf-8

%w{flickraw tempfile fileutils yaml}.each { |lib| require lib }

dataDirName = File.expand_path "~/Library/Application Support/flickrbackup"
FileUtils.mkpath dataDirName

ID_SEP = ' -> '
AS_SEP = "\u0000"

def loadIDsFileNamed(fileName, many2many = false)
  FileUtils.touch fileName
  idHash = {}
  fileData = open(fileName).each_line do |line| 
    id1, id2 = line.chomp.split ID_SEP
    many2many ? (idHash[id1] ||= {})[id2] = true : idHash[id1] = id2
  end
  idHash
end

def appendToIDsFile(fp, id1, id2, fsync = true)
  dataRecord = "#{id1}#{ID_SEP}#{id2}"
  fp.puts dataRecord
  fp.fsync if fsync
  dataRecord
end

def applescript(source, *args)
  IO.popen(['osascript', '-', *args], 'w') { |io| io.write(source) }
end

def loadASOutputFileNamed(fileName)
  open(fileName, 'rb:utf-16be:utf-8').each_line(AS_SEP).map { |datum| datum.chomp AS_SEP }
end

def takeLongEnough
  startTime = Time.now
  returnValue = yield
  timeTaken = Time.now - startTime
  timeToSleep = 1.01 - timeTaken  # rate limit to just under 3600 reqs/hour
  sleep timeToSleep if timeToSleep > 0
  returnValue
end


# load or get Flickr credentials

credentialsFileName = "#{dataDirName}/credentials.yaml"

if File.exist? credentialsFileName
  credentials = YAML.load_file credentialsFileName
  FlickRaw.api_key        = credentials[:api_key] 
  FlickRaw.shared_secret  = credentials[:api_secret]
  flickr.access_token     = credentials[:access_token]
  flickr.access_secret    = credentials[:access_secret]
  login = flickr.test.login
  puts "Authenticated as: #{login.username}"

else
  print "Flickr API key: "
  FlickRaw.api_key = gets.strip
  
  print "Flickr API shared secret: "
  FlickRaw.shared_secret = gets.strip
  
  token = flickr.get_request_token
  auth_url = flickr.get_authorize_url(token['oauth_token'], :perms => 'write')
  print "Authorise access to your Flickr account: press [Return] when ready"
  gets
  `open '#{auth_url}'`

  print "Authorisation code: "
  verify = gets.strip
  flickr.get_access_token(token['oauth_token'], token['oauth_token_secret'], verify)
  login = flickr.test.login
  puts "Authenticated as: #{login.username}"

  credentials = {api_key:       FlickRaw.api_key, 
                 api_secret:    FlickRaw.shared_secret, 
                 access_token:  flickr.access_token,
                 access_secret: flickr.access_secret}

  File.open(credentialsFileName, 'w') { |credentialsFile| YAML.dump(credentials, credentialsFile) }
end


# load own backup records

uploadedPhotosFileName = "#{dataDirName}/uploaded-photo-ids-map.txt"
createdAlbumsFileName  = "#{dataDirName}/created-album-ids-map.txt"
photosInAlbumsFileName = "#{dataDirName}/photos-in-album-ids-map.txt"

uploadedPhotosHash  = loadIDsFileNamed uploadedPhotosFileName
createdAlbumsHash   = loadIDsFileNamed createdAlbumsFileName
photosInAlbumsHash  = loadIDsFileNamed photosInAlbumsFileName, true


# get all iPhoto IDs and paths, and filter out those already backed up

photosAS = %[
on run argv
  set text item delimiters to ASCII character 0
  tell application "iPhoto" to set snaps to {id, image path} of photos in photo library album
  
  set ids     to first item of snaps
  set idsFile to first item of argv
  writeUnicodeToPOSIXFile(idsFile, ids as Unicode text)
  
  set paths     to second item of snaps
  set pathsFile to second item of argv
  writeUnicodeToPOSIXFile(pathsFile, paths as Unicode text)
end run

on writeUnicodeToPOSIXFile(fileName, contents)
  set fp to open for access (POSIX file fileName) with write permission
  write contents to fp as Unicode text
  close access fp
end writeToFile
]

idsFile   = Tempfile.new 'ids'
pathsFile = Tempfile.new 'paths'
[idsFile, pathsFile].each { |f| f.close }
applescript(photosAS, idsFile.path, pathsFile.path)
allIDs   = loadASOutputFileNamed(idsFile).map { |id| id.to_f.to_i.to_s }
allPaths = loadASOutputFileNamed(pathsFile)
[idsFile, pathsFile].each { |f| f.unlink }

allPhotoData = allIDs.zip(allPaths)
newPhotoData = allPhotoData.reject { |photoData| uploadedPhotosHash[photoData.first] }

puts "\n#{allPhotoData.length} photos in iPhoto library"
puts "#{newPhotoData.length} photos not yet uploaded to flickr\n"


# get all iPhoto albums and associated photo IDs

albumsAS = %[
on run argv
  set text item delimiters to ASCII character 0
  set nul to {"", ""} as Unicode text

  set albumsFile to first item of argv
  set fp to open for access (POSIX file albumsFile) with write permission

  tell application "iPhoto"
    repeat with anAlbum in albums
      if anAlbum's type is regular album then
        set albumName to anAlbum's name
        if albumName is not "Last Import" then
          set albumPhotoIds to (id of every photo of anAlbum) as Unicode text
          if length of albumPhotoIds is greater than 0 then
            set currentAlbum to anAlbum
            repeat while currentAlbum's parent exists
              set currentAlbum to currentAlbum's parent
              set albumName to currentAlbum's name & " > " & albumName
            end repeat
            set albumId to anAlbum's id

            set albumData to {"", albumId, albumName, ""} as Unicode text
            write albumData to fp as Unicode text
            write albumPhotoIds to fp as Unicode text
            write nul to fp as Unicode text
          end if
        end if
      end if
    end repeat
  end tell

  close access fp
end run
]

albumsFile = Tempfile.new 'albums'
albumsFile.close
applescript(albumsAS, albumsFile.path)
rawAlbumData = loadASOutputFileNamed(albumsFile)
albumsFile.unlink

albumEnum = rawAlbumData.each
albumData = {}
loop do
  albumEnum.next while albumEnum.peek.empty?
  albumId       = albumEnum.next.to_f.to_i.to_s
  albumName     = albumEnum.next
  albumPhotoIds = []
  while not (nextId = albumEnum.next).empty?
    albumPhotoIds << nextId.to_f.to_i.to_s
  end
  albumData[albumId] = {name: albumName, photoIDs: albumPhotoIds} unless albumPhotoIds.empty?
end


# upload new files

open(uploadedPhotosFileName, 'a') do |uploadedPhotosFile|

  newPhotoData.each_with_index do |photoData, i|
    iPhotoID, photoPath = photoData
    
    begin
      print "#{i + 1}. Uploading '#{photoPath}' ... "
      flickrID = takeLongEnough { flickr.upload_photo photoPath }
    # keep trying in face of network errors: Timeout::Error, Errno::BROKEN_PIPE, SocketError, ...
    rescue => err  
      print "#{err.message}: retrying in 10s "; 10.times { sleep 1; print '.' }; puts
      retry
    end
    puts appendToIDsFile(uploadedPhotosFile, iPhotoID, flickrID)

  end
end


# reload uploaded photo records (in case we need to add any newly-uploaded photos to albums)

uploadedPhotosHash = loadIDsFileNamed uploadedPhotosFileName


# update albums/photosets

puts "\n#{albumData.length} standard albums in iPhoto\n"

open(createdAlbumsFileName, 'a') do |createdAlbumsFile|
open(photosInAlbumsFileName, 'a') do |photosInAlbumsFile|

  albumData.each do |albumID, album|
    photosetID = createdAlbumsHash[albumID]

    if photosetID.nil?

      flickrPhotoIDs = album[:photoIDs].map { |id| uploadedPhotosHash[id] }
      print "Creating new photoset: '#{album[:name]}' ... "
      photosetID = takeLongEnough { flickr.photosets.create(title: album[:name], primary_photo_id: flickrPhotoIDs.first).id }
      puts appendToIDsFile(createdAlbumsFile, albumID, photosetID)

      print "Adding #{flickrPhotoIDs.length} photos to new photoset ... "
      takeLongEnough { flickr.photosets.editPhotos(photoset_id: photosetID, photo_ids: flickrPhotoIDs.join(','), primary_photo_id: flickrPhotoIDs.first) }
      album[:photoIDs].each { |iPhotoID| appendToIDsFile(photosInAlbumsFile, iPhotoID, albumID, false) }
      photosInAlbumsFile.fsync
      puts "done"

    else
      # add any new photos
      album[:photoIDs].each do |iPhotoID|
        albumsForPhoto = photosInAlbumsHash[iPhotoID]
        photoIsInAlbum = albumsForPhoto && albumsForPhoto[albumID]

        unless photoIsInAlbum
          flickrPhotoID = uploadedPhotosHash[iPhotoID]
          print "Adding photo #{iPhotoID} -> #{flickrPhotoID} to photoset #{albumID} -> #{photosetID} ... "
          takeLongEnough { flickr.photosets.addPhoto(photoset_id: photosetID, photo_id: flickrPhotoID) }
          appendToIDsFile(photosInAlbumsFile, iPhotoID, albumID)
          puts "done"
        end
      end

    end
  end

end
end
