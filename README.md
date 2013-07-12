# patrick

Synchronize a Git repository from one place to another.

![](http://i.qkme.me/3v5agm.jpg)

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
patrick.mirror '/repos/there', snapshot, (error) ->
  if error?
    console.error('mirror failed', error)
  else
    console.log('mirror succeeded')
```
