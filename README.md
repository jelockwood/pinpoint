# pinpoint
A script for finding your Mac

URGENT - 
Apple have deprecated their airport binary as of macOS Sonoma 14.4 and as a result currently this script will not work in macOS Sonoma 14.4 or later. It does still work under macOS 14.3.1 or earlier.

I have already determined that it should be possible to use a Python script to obtain the same information that the airport binary previously provided. Ironically one of the goals I set myself originally was to write this script in a way that did not require using Python at all as Apple had stopped incuding a copy of Python in macOS.

Update -
I have discovered also that as Python is using the CoreWIFI api, this requires enabling Location Services as well. Unfortunately it is effectively impossible to enable Location Services for root to use as required by IT management tools like Jamf Pro and MunkiReport. I have therefore since created a shell script which does not require Location Services or Python or CoreWIFI but has the very small drawback of not producing quite as much information. It does however seem to be sufficient.

I have also been able to use a copy of the airport binary from macOS 14.3.1 in macOS 14.4 successfully but this cannot be relied on for the future.

![pinpoint logo](/support_files/pinpoint-logo.png)
Image created by Macrovector - [Freepik.com](https://www.freepik.com/free-photos-vectors/label)

Author: John Lockwood - https://jelockwood.blogspot.co.uk  

# Info

pinpoint is a script that is able to find the location of your Mac using Google's GeoLocation APIs. In order to use Google's GeoLocation APIs you need to obtain an API key. As of July 16th 2018 you also need to enable billing on your account for your API key aka Project. As far as I can see you get a $200 per month credit and this should be enough for 10,000 uses of Geolocation, Geocoding and Elevation APIs _each_. See [Wiki](https://github.com/jelockwood/pinpoint/wiki).

This version is a completely written from scratch replacement for the now deprecated original python version written by Clayton Burlison. See https://github.com/clburlison/pinpoint Clayton has kindly given his permission for me to re-use the name of his original project and to design mine as a drop-in replacement.

Clayton's version relied heavily on Apple's Location Services API which sadly as of High Sierra 10.13.4 Apple changed so that it became impossible to use in an automated fashion. This version as mentioned has been written from scratch and does not use Location Services at all and hence is able to work - even in Mojave 10.14.

More information about this version can be found on the [Wiki](https://github.com/jelockwood/pinpoint/wiki).

:bangbang: Munkireport users [read this](https://github.com/jelockwood/pinpoint/wiki/MunkiReport-Setup)! :bangbang:

# Legal Notice

> pinpoint should only be installed on devices that you have authorization to do so on. Data collected from this project is directly uploaded to Google, Inc. via Geocoding APIs for in order to locate your Mac.
>
> Usage of this project for illegal or immoral activities is deeply frowned upon. These activities could have consequences including fines and jail time depending on your location. I in no way endorse the usage of this project for these acts.

I am not a lawyer and all questions regarding the legality of this project within a specific organization should be taken up with a real lawyer.


# Credits
Based off of works by: [Clayton Burlison](https://github.com/clburlison/pinpoint/)
