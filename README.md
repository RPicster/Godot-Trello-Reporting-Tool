
# Godot - Trello Reporting Tool
**A tool to create Trello cards and add attachments from an in-game Godot interface.**


![Image of the interface](https://raw.githubusercontent.com/RPicster/Godot-Trello-Reporting-Tool/556f7be7b60ceec762193b35c44bda372d7caf27/icon.png)

### How to use:

All you need inside your Godot project are the files `src\Trello_Reporting_Tool.gd` and `src\Trello_Reporting_Tool.tscn`. Copy those into your project and apply a theme to your liking.

Thanks to the fantastic contributions of [@aszlig](https://github.com/aszlig) the tool now uses a proxy to make easy access to the Trello key and token through reverse engineering of the projects gdscript impossible.

### Setup the Proxy

To setup the proxy, edit the following lines inside the `src\proxy.php`:

    const TRELLO_KEY = '@YOUR_TRELLO_API_KEY@';
    const TRELLO_TOKEN = '@YOUR_TRELLO_API_TOKEN@';

To get a Trello key and token combination, visit https://trello.com/app-key. You need a Trello account for it to work 😉

    const TRELLO_LIST_ID = '@YOUR_TRELLO_LIST_ID@';

To find out the list id ( to setup in which lists the cards are created), visit your Trello board, click on a card inside the list you want to use, add `.json` to the end of the URL in your browser and find the value `idList` in the json file.

With the proxy.php setup, copy the file onto a public accessible webserver of your choice.

### Setup the GDscript
Inside the Trello_Reporting_Tool.gd there are two lines to setup to have the basic functionality:

    const  PROXY_URL = 'https://proxy.example/proxy.php'
Use the URL to the proxy.php file on your webserver.

Next step is to setup the Labels, if you want to use any:

    var trello_labels = {
	    0 : {
		    "label_trello_id" : "LABEL ID FROM TRELLO",
		    "label_description" : "Label name for Option Button"
	    },
	    1 : {
		    "label_trello_id" : "LABEL ID FROM TRELLO",
		    "label_description" : "Label name for Option Button"
	    }
    }

You can add as many labels as Trello supports. The easiest way to find out the Trello label id, is similar to the way of finding the list id. By navigating to a card in trello that has the label you want to use, add `.json` to the URL and look for `labels`. The id listed at those entries is the label id you are looking for.

If you don't want to use any labels, just use an empty dictionary for trello_labels:

    var  trello_labels = {}

### Setup the Attachments

The final step is to setup the attachments inside the GDScript:

    data['cover'] = Attachment.from_path("res://icon.png")
    
    data['attachments'] = [
	    Attachment.from_image(
	    OpenSimplexNoise.new().get_image(200, 200), 'noise1'
	    ),
	    Attachment.from_image(
	    OpenSimplexNoise.new().get_image(200, 200), 'noise2'
	    ),
    ]

The first line will be the attachment that is used as the cover image for the card - `data['cover']`
**This has to be an image file of any kind.**
You can either use the Attachment class method `from_image()` to add an attachment directly from a Godot `Image` class or use the Attachment class method `from_file()` to attach an image from a filepath (*accessible from your project*)

The same methods are used in the `data['attachments']`. You can add as many attachments as you like. Or none at all.

### How to use in your Project

The script has a method to show and reset the form: `show_window()`
Calling this method will reset the window and make it visible.
