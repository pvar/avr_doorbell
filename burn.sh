#! /bin/bash
sudo avrdude -p m328p -c usbasp -U flash:w:main.hex:i
