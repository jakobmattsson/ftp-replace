fs    = require 'fs'
path  = require 'path'
ftp   = require 'ftp'
async = require 'async'

exports.upload = (params, done) ->
  done = done ? ->
  params.log = params.log ? ->

  ftplist = (directory, callback) ->
    files = []
    dirs = []
    conn.list directory, (e, entries) ->
      return callback(e) if e
      entries.forEach (entry) ->
        if entry.type == "-"
          files.push(path.join(directory, entry.name))
        else if entry.type == "d"
          dirs.push(path.join(directory, entry.name))
      callback(null, files, dirs)

  recDelete = (directory, complete) ->
    params.log("traversing: " + directory)
    ftplist directory, (err, files, dirs) ->
      return complete(err) if err
      async.forEachSeries dirs, (item, callback) ->
        recDelete(item, callback)
      , (err) ->
        return complete(err) if err
        async.forEachSeries files, (item, callback) ->
          params.log("deleting file: " + item)
          conn.delete(item, callback)
        , (err) ->
          return complete(err) if err
          params.log("deleting directory: " + directory)
          conn.rmdir directory, (err) ->
            if err && err.code == 550
              params.log("The directory is not empty, retry...")
              recDelete(directory, complete)
            else
              complete.apply(null, arguments)

  recUpload = (directory, dst, complete) ->
    fs.readdir directory, (err, files) ->
      async.forEachSeries files, (file, callback) ->
        fs.stat path.join(directory, file), (err, stat) ->
          return callback(err) if err
          if stat.isFile()
            unless file.charAt(0) == "."
              sourceFile = path.join(directory, file)
              fileSize = fs.statSync(sourceFile).size
              stream = fs.createReadStream(sourceFile)
              readBytes = 0
              stream.on "data", (chunk) ->
                readBytes += chunk.length
                params.log "uploading: " + sourceFile + " (" + Math.floor(100 * readBytes / fileSize) + " %)"
              conn.put stream, path.join(dst, file), callback
            else
              callback()
          else
            params.log("creating dir: " + path.join(dst, file))
            conn.mkdir path.join(dst, file), (err) ->
              return callback(err) if err
              recUpload(path.join(directory, file), path.join(dst, file), callback)
      , complete

  conn = new ftp {
    host: params.host
    debug: (str) ->
  }

  conn.on "connect", ->
    conn.auth params.username, params.password, (e) ->
      throw e if e
      fs.readdir params.sourceDir, (err, files) ->
        return done(err) if err
        async.forEachSeries files, (file, callback) ->
          fs.stat path.join(params.sourceDir, file), (err, stat) ->
            return callback(err) if err
            if stat.isFile()
              params.log "deleting file: " + path.join(params.targetDir, file)
              conn["delete"] path.join(params.targetDir, file), (err) ->
                if err and err.message isnt "Server Error: 550 File not found"
                  return callback(err)
                callback()
            else
              recDelete path.join(params.targetDir, file), (err) ->
                if err and err.message isnt "Server Error: 550 Directory not found."
                  return callback(err)
                callback()
        , (err) ->
          if err
            params.log err
          else
            params.log "done deleting. now uploading"
            recUpload params.sourceDir, params.targetDir, (err) ->
              conn.end()
              done err

  conn.connect()
