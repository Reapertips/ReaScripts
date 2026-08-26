# Reapertips ReaScripts

Free scripts for REAPER by [Reapertips](https://www.reapertips.com) 💙

# 📦 Install

In REAPER, go to `Extensions` > `ReaPack` > `Import repositories...` and paste this:

```
https://github.com/Reapertips/ReaScripts/raw/master/index.xml
```

Then go to `Extensions` > `ReaPack` > `Browse packages...` and install whatever you want!

Don't have ReaPack yet? No worries! – here's [how to install it](https://reapertips.com/post/how-to-install-reapack).

### Packages

## 🎸 TunerBox
<img src="https://i.imgur.com/K95PRbP.png" alt="TunerBox" width="800">

A chromatic tuner that lives right in your transport bar. Click the tuning fork to turn it on, click the readout for a big tuner window, and right click for options. It also remembers how you set it up for each theme.

This one needs the **js_ReaScriptAPI** extension. ReaPack will offer to install it for you.

## 🔴 Time selection color for loop and record
<img src="https://i.imgur.com/ikfAVee.png" alt="Time selection color for loop and record" width="800">

Tints your time selection while Repeat/Loop is on, and again while REAPER is recording, so you can tell both states apart without looking away from what you're doing.

Each state decides on its own which areas it paints: arrange, MIDI editor, ruler, or the whole ruler strip as an adjustable tint. Colors are remembered per theme, and the settings window has a live preview.

Nothing extra to install, and colors are only changed in memory, so your theme file is never touched. 

## 🎸 Speed Trainer
<img src="https://i.imgur.com/0Fvigao.png" alt="Speed Trainer" width="800">

If there's a difficult section of a song you can play slowly but struggle to
reach at full speed, **Speed Trainer helps you build up to it gradually!**

Select the section, choose your starting speed and target, then decide how
quickly you wanna get there. For example, you can start at **70%**, increase
the speed by **5% every three loops**, and keep practicing until you reach
**100%**.

Speed Trainer handles the speed changes while you play. The ring shows where
you are inside each repetition and warns you before the next increase. You can
also add a count-in, hold the current speed, go back, advance, pause or stop at
any time.

You also get four companion actions for keyboard shortcuts, toolbar buttons or
a MIDI footswitch. Super useful when your hands are busy playing!

Speed Trainer changes REAPER's master playrate without editing your tempo map.
If there isn't enough room for the count-in, it can insert the required bars at
the start of the project in one undoable step.

You need **REAPER 7.0 or newer** and **ReaImGui 0.10 or newer**.

# License

MIT. Check [LICENSE](LICENSE) for the third party notices.
