# Quiver Analytics
[Quiver Analytics](https://quiver.dev/analytics/) allows you to collect analytics for games made with the [Godot engine](https://godotengine.org) in a privacy-friendly way. In just a few minutes, you can integrate Analytics in your game through this open source plugin and gain valuable insight into how players are interacting with your game. You also have fine-grained control over how your players' privacy is handled.

## Guidelines
Before you get started, note that Quiver Analytics is meant to be used to collect non-identifying information about your players to understand how your game is played while respecting their privacy. Please do not send personal information like names, email addresses, physical addresses, phone numbers, IP addresses, or any other identifying information to Quiver Analytics. Doing so may cause your account to be restricted. If you have any questions, [give us a shout](https:/quiver.dev/contact/).

## Prerequisites
This plugin requires Godot 4.0 or later. It's been designed to work with GDScript. We'll add support for other languages in the future.

## Installation
* Create an account on [quiver.dev](https://quiver.dev).
* [Create a project](https://quiver.dev/projects/up/) on Quiver associated with your game.
* Enable Analytics by going to to the [Quiver Analytics page](https://quiver.dev/analytics/), going to the Settings tab, and copying the authentication token from there.
* Grab this plugin from the Godot Asset Library (use the AssetLib view in the Godot editor) or copy the `quiver_analytics` directory in the [Github repo](https://github.com/quiver-dev/quiver-analytics-godot-plugin) to the `/addons/` directory in your project root.
* Go to your Project Settings -> Plugins and make sure Quiver Analytics is enabled.
* Close Project Settings and reopen it again. Go to the General tab and you should see a new "Quiver" section at the bottom of the left window.
* Go to Quiver -> Analytics in Project Settings and set your auth token to the token you created on the website.
* Run your game (the default settings should post a "Game launched" event to your dashboard).
* [View the dashboard](https://quiver.dev/analytics/) to see the new event.

## Usage
The `Analytics` autoload is added to your project automatically when you enable the plugin. 

### Adding an event
To send an event, call:

`Analytics.add_event(event_name, properties)`

where `event_name` is the name of the event (should be 50 characters or less) and `properties` is an optional dictionary with key/values with additional properties that describe the event. 

Here's an example:

`Analytics.add_event("Completed level", {"level": 2, "usedSpecialPower": false})`

By default, player consent isn't required for anonymous data collection, but if you activate required consent, calls to this function will be ignored until consent is received.

### Cleaning up before exiting the game

Before you quit the game, you can tell the plugin to send a configurable "Quit game" event and flush any outstanding events. To do that, write this code anywhere you are exiting the game:

`await Analytics.handle_exit()`

Note that SceneTree.quit() will immediately exit the game so you want to make sure you wait for the above call to finish before calling the quit() function.

#### _Note for web and mobile games:_

If you are developing a web or mobile game, it might be difficult to call `handle_exit()` since you don't always have the option to run operations when a player backgrounds the app or closes the tab. To work around this, we have added some special logic to automatically add 'Quit game' events. Note that the timing of this event is an estimate and might be up to a minute off the actual quit time. 

## Advanced Usage
The following is not required, but you do have additional functionality if you need it.

### Managing consent

By default, the plugin won't ask for consent since no personally identifying information is collected. However, you can enable opt-in data collection by going to Project Settings -> Quiver -> Analytics and set "Player Consent Required" to true. Now calls to `add_event()` will be ignored until you obtain consent. To manage consent, you can either use the built-in UI:

	if Analytics.should_show_consent_dialog():
	  Analytics.show_consent_dialog(parent_node)

 This will decide whether consent has already been granted or denied and, if not, will spawn a consent dialog as a child of the parent_node.

If you'd like to use your own UI and manually handle consent management, you can use the following functions:

	# Variable storing whether consent has been requested
	Analytics.consent_requested
	# Variable storing consent status
	Analytics.consent_granted
	# Function to call if consent was granted
	Analytics.approve_data_collection()
	# Function to call if consent was denied
	Analytics.deny_data_collection()

### Customizing consent UI
By default, the built-in consent UI will use whatever UI theme that has been set for your project. You can modify this by changing the properties of the ConsentDialog found in `/addons/quiver_analytics/consent_dialog.tscn`.

### Advanced Properties
If you turn on Advanced Settings for Project Settings -> Quiver -> Analytics, you'll find the following properties:

* "Config File Path": where the config file is stored, defaults to "user://analytics.cfg".
* "Auto Add Event on Launch": whether a "Launched game" event is sent automatically when the game starts, defaults to true.
* "Auto Add Event on Quit": whether a "Quit game" event is sent automatically, defaults to true.

### Notes and Limitations

* Events are queued up and sent after some delay to prevent overloading the analytics server and negatively affecting game performance.
* No more than 50 events can be sent in a minute to prevent the server from being overloaded from bursts of events.
* Event names must be 50 characters or less.
* If an event fails to send due to network or server issues, it will be retried with exponential backoff.
* If `Analytics.handle_exit()` is called when the game is exited but any queued events fail to send, they'll be saved to disk and loaded the next time the game starts.
* If the events saved to disk exceed more than 200 events, events will start to be dropped, starting with the oldest. This is to avoid performance issues with loading a large file of saved events.

### License

MIT License
