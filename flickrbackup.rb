#!/usr/bin/env ruby
# encoding: utf-8

# https://github.com/jawj/iphoto-flickr

# Copyright (c) George MacKerron 2013, http://mackerron.com
# Released under GPLv3: http://opensource.org/licenses/GPL-3.0


%w{flickraw-cached tempfile fileutils yaml logger colorize}.each { |lib| require lib }

logger = Logger.new STDOUT
logger.formatter = proc { |severity, t, progname, msg| "#{t}  #{msg}" }

puts


# own records setup

dataDirName = File.expand_path "~/Library/Application Support/flickrbackup"
FileUtils.mkpath dataDirName

class PersistedIDsHash  # in retrospect, perhaps this was a job for SQLite ...
  ID_SEP = ' -> '
  def initialize(fileName)
    @hash = {}
    FileUtils.touch fileName
    open(fileName).each_line do |line|
      k, v = line.chomp.split ID_SEP
      store k, v
    end
    open(fileName, 'a') do |file|
      @file = file
      yield self
    end
  end
  def add(k, v)
    store k, v
    record = "#{k}#{ID_SEP}#{v}"
    @file.puts record
    @file.fsync
    record
  end
  def get(k)
    @hash[k]
  end
private
  def store(k, v)
    @hash[k] = v
  end
end

class PersistedIDsHashMany < PersistedIDsHash
  def associated?(k, v)
    @hash[k] && @hash[k][v]
  end
private
  def store(k, v)
    (@hash[k] ||= {})[v] = true
  end
end


# AppleScript setup

AS_SEP = "\u0000"

def applescript(source, *args)
  IO.popen(['osascript', '-', *args], 'w') { |io| io.write(source) }
end

def loadOutputFile(fileName)
  open(fileName, 'rb:utf-16be:utf-8').each_line(AS_SEP).map { |datum| datum.chomp AS_SEP }
end


# Flickr API setup

FlickRaw.secure = true

credentialsFileName = "#{dataDirName}/credentials.yaml"

if File.exist? credentialsFileName
  logger.info "Authenticating ...\n"
  credentials = YAML.load_file credentialsFileName
  FlickRaw.api_key        = credentials[:api_key]
  FlickRaw.shared_secret  = credentials[:api_secret]
  flickr.access_token     = credentials[:access_token]
  flickr.access_secret    = credentials[:access_secret]
  login = flickr.test.login
  logger.info "Authenticated as: #{login.username}".green + "\n\n"

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
  puts
  logger.info "Authenticated as: #{login.username}".green + "\n\n"

  credentials = {api_key:       FlickRaw.api_key,
                 api_secret:    FlickRaw.shared_secret,
                 access_token:  flickr.access_token,
                 access_secret: flickr.access_secret}

  File.open(credentialsFileName, 'w') { |credentialsFile| YAML.dump(credentials, credentialsFile) }
end

def rateLimit
  startTime = Time.now
  returnValue = yield
  timeTaken = Time.now - startTime
  timeToSleep = 1.01 - timeTaken  # rate limit to just under 3600 reqs/hour
  sleep timeToSleep if timeToSleep > 0
  returnValue
end


# load own backup records

PersistedIDsHash.new("#{dataDirName}/uploaded-photo-ids-map.txt") do |uploadedPhotos|
PersistedIDsHash.new("#{dataDirName}/created-album-ids-map.txt") do |createdAlbums|
PersistedIDsHashMany.new("#{dataDirName}/photos-in-album-ids-map.txt") do |photosInAlbums|


# get all iPhoto IDs and paths, and filter out those already backed up

logger.info "Getting list of photos from iPhoto (could take a while) ...\n"

photosAS = %[
on run argv
  with timeout of 3600 seconds
    set text item delimiters to character id 0
    tell application "iPhoto" to set snaps to {id, original path, image path} of photos in photo library album

    set ids     to first item of snaps
    set idsFile to first item of argv
    writeUnicodeToPOSIXFile(idsFile, ids as Unicode text)

    set paths     to second item of snaps
    set pathsFile to second item of argv
    writeUnicodeToPOSIXFile(pathsFile, paths as Unicode text)

    set fallbackPaths     to third item of snaps
    set fallbackPathsFile to third item of argv
    writeUnicodeToPOSIXFile(fallbackPathsFile, fallbackPaths as Unicode text)
  end timeout
end run

on writeUnicodeToPOSIXFile(fileName, contents)
  set fp to open for access (POSIX file fileName) with write permission
  write contents to fp as Unicode text
  close access fp
end writeToFile
]

idsFile, pathsFile, fallbackPathsFile = Tempfile.new('ids'), Tempfile.new('paths'), Tempfile.new('fallbackPaths')
[idsFile, pathsFile, fallbackPathsFile].each { |f| f.close }
applescript(photosAS, idsFile.path, pathsFile.path, fallbackPathsFile.path)
allIDs = loadOutputFile(idsFile).map { |id| id.to_f.to_i.to_s }
allPaths, allFallbackPaths = loadOutputFile(pathsFile), loadOutputFile(fallbackPathsFile)
[idsFile, pathsFile, fallbackPathsFile].each { |f| f.unlink }

allPhotoData = allIDs.zip(allPaths, allFallbackPaths)
newPhotoData = allPhotoData.reject { |photoData| uploadedPhotos.get photoData.first }

# get all iPhoto albums and associated photo IDs

logger.info "Getting album data from iPhoto (could also take a while) ...\n\n"

albumsAS = %[
on run argv
  with timeout of 3600 seconds
    set nul to character id 0
    set text item delimiters to nul

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
              tell me
                write albumData to fp as Unicode text
                write albumPhotoIds to fp as Unicode text
                write nul to fp as Unicode text
              end tell
            end if
          end if
        end if
      end repeat
    end tell

    close access fp
  end timeout
end run
]

albumsFile = Tempfile.new 'albums'
albumsFile.close
applescript(albumsAS, albumsFile.path)
rawAlbumData = loadOutputFile(albumsFile)
albumsFile.unlink

albumEnum = rawAlbumData.each
albumData = {}
loop do
  albumEnum.next while albumEnum.peek.empty?
  albumId = albumEnum.next.to_f.to_i.to_s
  albumName = albumEnum.next
  albumData[albumId] = {name: albumName, photoIDs: []}
  albumPhotoIds = albumData[albumId][:photoIDs]
  while not (nextId = albumEnum.next).empty?
    albumPhotoIds << nextId.to_f.to_i.to_s
  end
end

logger.info "#{allPhotoData.length} photos and #{albumData.length} standard albums in iPhoto library\n"
logger.info "#{newPhotoData.length} photos not yet uploaded to Flickr".green + "\n\n"


# upload new files

MAX_SIZE   = 1024 ** 3
MAX_RETRY  = 6
RETRY_WAIT = 10

class ErrTooBig < RuntimeError; def to_s; 'File is too big'; end; end

newPhotoData.each_with_index do |photoData, i|
  iPhotoID, photoPath, fallbackPhotoPath = photoData
  photoPath = fallbackPhotoPath unless File.exist? photoPath  # fall back to 'image path' if 'original path' missing

  retries = 0

  begin
    logger.info "(#{i + 1}/#{newPhotoData.length})  Uploading '#{photoPath}' ... "
    raise ErrTooBig if File.size(photoPath) > MAX_SIZE
    flickrID = rateLimit { flickr.upload_photo photoPath }
    raise 'Invalid Flickr ID returned' unless flickrID.is_a? String  # this can happen, but I'm not yet sure what it means
    puts uploadedPhotos.add iPhotoID, flickrID

  rescue ErrTooBig, Errno::ENOENT, Errno::EINVAL => err  # in the face of missing/large/weird files, don't retry
    puts err.message.yellow

  # keep trying indefinitely in face of network errors
  rescue Timeout::Error, Errno::EPIPE, SocketError => err
    print "#{err.message}: retrying soon ".yellow; RETRY_WAIT.times { sleep 1; print '.' }; puts
    retry

  # other errors MAY or MAY NOT not be recoverable, so try a few times and then give up
  rescue => err
    retries += 1
    if retries > MAX_RETRY
      puts "skipped: retry count exceeded".red
    else
      print "#{err.message}: retrying soon (#{retries}/#{MAX_RETRY}) ".yellow; RETRY_WAIT.times { sleep 1; print '.' }; puts
      retry
    end
  end

end


# update albums/photosets

SET_NOT_FOUND   = 1
PHOTO_NOT_FOUND = 2

albumData.each do |albumID, album|
  photosetID = createdAlbums.get albumID

  if photosetID.nil?
    logger.info "Creating new photoset: '#{album[:name]}' ... "
    somePhotoID = album[:photoIDs].first
    someFlickrPhotoID = uploadedPhotos.get somePhotoID

    begin
      photosetID = rateLimit { flickr.photosets.create(title: album[:name], primary_photo_id: someFlickrPhotoID).id }

    rescue FlickRaw::FailedResponse => e
      if e.code == PHOTO_NOT_FOUND  # photoset cannot be created if primary photo has been deleted from Flickr
        print e.msg.yellow, ' ... '
        photosetID = 'X'
      else raise e
      end
    end

    puts createdAlbums.add albumID, photosetID
    photosInAlbums.add somePhotoID, albumID
  end

  # add any new photos
  album[:photoIDs].each do |iPhotoID|

    unless photosInAlbums.associated? iPhotoID, albumID
      flickrPhotoID = uploadedPhotos.get iPhotoID
      logger.info "Adding photo #{iPhotoID} -> #{flickrPhotoID} to photoset #{albumID} -> #{photosetID} ... "
      errorHappened = false

      begin
        rateLimit { flickr.photosets.addPhoto(photoset_id: photosetID, photo_id: flickrPhotoID) }
      rescue FlickRaw::FailedResponse => e
        if [SET_NOT_FOUND, PHOTO_NOT_FOUND].include? e.code
          puts e.msg.yellow
          errorHappened = true
        else raise e
        end
      end

      puts "done" unless errorHappened
      photosInAlbums.add iPhotoID, albumID
    end
  end

end

end; end; end  # own records blocks
puts  # I prefer some whitespace before the prompt
