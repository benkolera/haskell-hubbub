Mandatory
=========
* Hubbub.subscriptionThread.checkSubscriber should wire Internal.doSubscriptionEvent
* Hubbub.publishThread needs to:
** Use a function in another file that isn't tied into the loop.
** Lookup subscriptions to topic
** Call http.PublishResource for each subscriber
* Flesh out API for Hubbub.
* Write scotty API on top of Hubbub.

Optional
========
* Time lens instead of Data.DateTime
* Lens for HttpResource
* Expiration of subscriptions.
* Retrying when the upstream and downstream servers fail.
