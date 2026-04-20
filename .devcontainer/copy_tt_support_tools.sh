#!/bin/sh
# copy_tt_support_tools.sh
# Copia o actualiza las herramientas de soporte de TinyTapeout en el workspace.

if [ ! -L tt ]; then
    cp -R /ttsetup/tt-support-tools tt
    cd tt && git pull && cd ..
fi
