Mandatory
=========
* Hubbub.subscriptionThread.checkSubscriber should wire Internal.doSubscriptionEvent
* Hubbub.publicationThread needs to be wired to Internal.doPublicationEvent
** Also should queue resulting distribution events
* Hubbub.distributionThread needs to be wired to Internal.doPublicationEvent
* Flesh out API for Hubbub.
* Write scotty API on top of Hubbub.

Optional
========
* Expiration of subscriptions.
* Retrying when the upstream and downstream servers fail.
