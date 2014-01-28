haskell-hubub
=============

A haskell implementation of the PubSubHubub spec:
https://code.google.com/p/pubsubhubbub/

This code is being written as a teaching aid for the Brisbane Functional
Programming Group (www.bfpg.org) to teach practical haskell things like project
structure, testing, using acid-state for persistence, consuming web apis using
http-conduit, producing web apis with scotty and simple in memory message
queuing using STM TChannels. 

PubSubHubbub Protocol Description
---------------------------------

A simple, open, server-to-server webhook-based pubsub (publish/subscribe)
protocol for any web accessible resources. 

Parties (servers) speaking the PubSubHubbub protocol can get near-instant
notifications (via webhook callbacks) when a topic (resource URL) they're
interested in is updated. 

The protocol in a nutshell is as follows:

* An resource URL (a "topic") declares its Hub server(s) in its HTTP Headers, via
Link: <hub url>;  . The hub(s) can be run by the publisher of the resource, or
can be acommunity hub that anybody can use: Google's, or Superfeedr. 
* A subscriber (a server that's interested in a topic), initially fetches the
resource URL as normal. If the response declares its hubs, the subscriber can
then avoid lame, repeated polling of the URL and can instead register with the
designated hub(s) and subscribe to updates. 
* The subscriber subscribes to the Topic URL from the Topic URL's declared Hub(s).
When the Publisher next updates the Topic URL, the publisher software pings the
Hub(s) saying that there's an update. 
* The hub efficiently fetches the published resource and multicasts the
new/changed content out to all registered subscribers. 
* The protocol is decentralized and free. No company is at the center of this
controlling it. Anybody can run a hub, or anybody can ping (publish) or
subscribe using open hubs. 

Topics Covered
--------------

* Basic Haskell Syntax
* Project Structure & Cabal Setup
* Unit testing via Tasty (HUnit)
* Acid State for persisting program state to disk in a transactional way.
* sqlite-simple for interacting with SQLite 
* Using STM to do very simple in memory message queuing.
* Http Conduit for making HTTP Requests
* Scotty for producing a HTTP API
* JSON Serialisation
* Websockets for pushing data to a browser client.

Running the apps
----------------

* First you'll need GHC and the haskell platform (or just cabal-install at the least): http://www.haskell.org/platform/
* In this project:
```
cabal sandbox init
# this installs and compiles all deps. Will take a bit
cabal install --flag=mocks --only-dependencies
cabal configure --flag=mocks 
cabal build
```
* Then run:
```
dist/hubbub/hubbub          # for the hubbub server
dist/hubbub-mock-publisher  # for the mock publisher
dist/hubbub-mock-subscriber #for the mock subscriber
```
* At this point, point your browser (Chrome is best) at http://localhost:5001 and http://localhost:5002 to poke the subscriber and publisher.

(Note that the subscriber and web page don't do anything in the way of restablishing connections or leases when they expire, but if you refresh the page it'll resubscribe to the hubbub server and should get updates again.)

(If you're fiddling with the code and on linux, the cabal-build-loop script may be useful. It recompiles the code and restarts the servers when you make a change. On OSX you can replicate inotifywait with hobbes http://hackage.haskell.org/package/hobbes)

Running the tests
-----------------
* First you'll need GHC and the haskell platform (or just cabal-install at the least): http://www.haskell.org/platform/
* In this project:
```
cabal sandbox init (if you haven't already done this. Only need to do it once)
cabal install --flag=tests --enable-tests --only-dependencies (Will install dependencies plus the test ones too)
cabal configure --flag=tests --enable-tests
cabal test
```
(If you're fiddling with the code and on linux, the cabal-test-loop script may be useful. It recompiles the code and runs the tests when you make a change. On OSX you can do a replicate inotifywait with http://hackage.haskell.org/package/hobbes)
