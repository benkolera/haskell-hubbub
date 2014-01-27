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

Probably talk for an hour and a half about this doing a exploration of the
codebase (or live coding?) which does a shallow dive of the following topics
that should be a great boost to get into haskell and do something productive. 

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

