#!/bin/bash

# Ce script impl�mente un serveur.
# Le script doit �tre invoqu� avec l'argument :                                                              
# PORT   le port sur lequel le serveur attend ses clients 

if [ $# -ne 1 ]; then
    echo "usage: $(basename $0) PORT"
    exit -1
fi

PORT="$1"

# D�claration du tube

FIFO="/tmp/$USER-fifo-$$"

# Il faut d�truire le tube quand le serveur termine pour �viter de
# polluer /tmp.  On utilise pour cela une instruction trap pour �tre sur de
# nettoyer m�me si le serveur est interrompu par un signal.

function nettoyage() { rm -f "$FIFO"; }
trap nettoyage EXIT

# on cr�e le tube nomm�

[ -e "FIFO" ] || mkfifo "$FIFO"


function accept-loop() {
    while true; do
		interaction < "$FIFO" | netcat -l -p "$PORT" > "$FIFO"
    done
}

# La fonction interaction lit les commandes du client sur entr�e standard
# et envoie les r�ponses sur sa sortie standard. 
#
# 	CMD arg1 arg2 ... argn                   
#                     
# alors elle invoque la fonction :
#                                                                            
#         commande-CMD arg1 arg2 ... argn                                      
#                                                                              
# si elle existe; sinon elle envoie une r�ponse d'erreur.

browseMode=false
currentDirectory='\'                 

function interaction() {
    local cmd args
    while true; do
		read cmd args || exit -1
		if $browseMode; then
			fun="browse-$cmd"
		else
			fun="commande-$cmd"
		fi
		if [ "$(type -t $fun)" = "function" ]; then
	    	$fun $args
	    elif [ "$fun" = "browse-exit" ]; then
	    	browseMode=false
		else
		   	commande-non-comprise $fun $args
		fi
		if $browseMode; then
			echo "vsh:>"
		fi
    done
}

# Les fonctions impl�mentant les diff�rentes commandes du serveur

function commande-list() {
	ls=$(ls archives)
	if [ -n "$ls" ]; then
		echo "Les archives pr�sentes sur le serveur sont : $ls"
	else
		echo "Pas d'archives pr�sente sur le serveur"
	fi
}

function commande-create() {
	nomArchive=$1
	if [ -n "$nomArchive" ]; then
		occurence=false
		for i in $(ls archives); do
			if [ "$nomArchive" = "$i" ]; then
				occurence=true
				break
			fi
		done
		if $occurence; then
			echo "cr�ation impossible, une archive porte d�j� ce nom"
		else
			echo "3:5" >> archives/$nomArchive
		fi
	else
		echo "cr�ation impossible, pas de nom fourni pour l'archive"
	fi
}

function commande-browse() {
	nomArchive=$1
	if [ -n "$nomArchive" ]; then
		browseMode=true
	else
		echo "navigation impossible, pas de nom fourni pour l'archive"
	fi
}

function browse-pwd() {
	echo $currentDirectory
}

function commande-extract() {
	echo "extract"
}

function commande-non-comprise() {
   echo "Le serveur ne peut pas interpr�ter cette commande : $1 $2"
}

# On accepte et traite les connexions

accept-loop
