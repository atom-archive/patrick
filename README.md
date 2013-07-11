# patrick

Synchronize a Git repository from one place to another.

![](https://github-images.s3.amazonaws.com/skitch/captionater_%7C_quickmeme-20130711-104249.jpg)

## Usage

```coffeescript
patrick = require 'patrick'
```

### Generate a snapshot

```coffeescript
patrick.snapshot '/repos/here', (error, snapshot) ->
  if error?
    console.error('snapshot failed', error)
  else
    console.log('snapshot succeeded')
```

### Mirror a snapshot

```coffeescript
patrick.mirror snapshot, '/repos/there', (error) ->
  if error?
    console.error('mirror failed', error)
  else
    console.log('mirror succeeded')
```
