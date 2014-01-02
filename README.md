haskell-hubub
=============

A haskell implementation of the PubSubHubub spec:
https://code.google.com/p/pubsubhubbub/ 

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
