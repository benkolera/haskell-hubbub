Mandatory
=========
* Lease seconds should be passed through in Http.checkSubscriptions
* Hubbub.subscriptionThread.checkSubscriber should wire into Http.checkSubscription
* Hubbub.publishThread needs to:
** Use a function in another file that isn't tied into the loop.
** Lookup subscriptions to topic
** Call http.PublishResource for each subscriber
* Split doSubscribe out of Hubbub.subscriptionThread into another file.
* Flesh out API for Hubbub.
* Write scotty API on top of Hubbub.

Optional
========
** Time lens instead of Data.DateTime
** Lens for HttpResource.