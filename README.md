
# Panorea

Just a software that plays music !




## WARNING !

Of course, if your ears explode, I'm not responsible, because you have FULLY read the policy, at ``` miscellaneous/licence.txt ```
## Installation

Install Panorea:

Firstly, you must download the repository ! 

```bash
  cd /path-to/panorea/
  sh install-files/build.sh
  sh install-files/install.sh
```
Of course, the software is designed for Linux OSes, if you happen to be on FreeBSD, you can install FreePascal compiler, and aplay. And then manually compile ``` panorea.pas ``` and place it in ``` bin/panorea ``` 
## Usage/Examples

Panorea export and read ".music" files
An example short music file is available at ```miscellaneous/tetris.music```

```bash
    panorea /path/to/file.music
```

You can create your own music,

Firstly, choose your notation system:

```bash
-- PANOREA --
1. English          (C4, Db4, E4...)
2. Italian / French (DO4, REb4, MI4...)
3. German           (C4, DES4, H4...)
Q. Quit
Choose your notation system: en 
```
But you can choose any of the options

Then, you can enter some notes
```bash
=== NOTATION SYSTEM SET UP ===
-> To play a note: NOTE_OCTAVE:DURATION
-> To make a REST / PAUSE: leave the note blank, type only :DURATION (e.g. :400)
-> MULTI-PROCESS POLYPHONY: Separate notes by / to trigger multiple aplays (e.g. C4/E4/G4:500)
-> Low notes (lower than C3) are not supported, these notes will do weird things.
==============================

Enter notes separated by spaces. Type "Q" to quit, "CLR" to clear screen.
Example: C4/E4/G4:400 :200 C4/F4/A4:400
Your partition:C4/E4/G4:400 :200 C4/F4/A4:400
```
Yes, I'm good at computers, not music ! I've just copy-pasted
## What Panorea stands for and how to pronouce it ?

Panorea stands for "Pascal Notes Reader"
    
* Pascal, because it is written in Pascal 
* Notes, because it directly reads notes (C4, D2…)
* Reader, of course, you understood !

You can pronouce it like you want.
However, if you want to match the meaning of this name, you may like to pronouce it "Pa-nuh-w-ree"(in British English) or "Pa-noh-ree" (in American English)



## Help ! 

This is the magic of open source, I gave you the code, fork it, or ask me if someone wants to be the new maintener. Or this project will die ! 
