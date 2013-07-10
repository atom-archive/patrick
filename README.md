# syncopy

Synchronize a Git repository from one place to another.

## Usage

```coffeescript
syncopy = require 'syncopy'
```

### Generate a snapshot

```coffeescript
syncopy.generate '/repos/here', (error, snapshot) ->
  if error?
    console.error('snapshot failed', error)
  else
    console.log('snapshot succeeded')
```

### Apply that snapshot

```coffeescript
syncopy.restore snapshot, '/repos/there', (error) ->
  if error?
    console.error('restore failed', error)
  else
    console.log('restore succeeded')
```
