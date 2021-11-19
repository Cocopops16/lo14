#!/bin/bash

# Ce script implémente un serveur.
# Le script doit être invoqué avec l'argument :                                                              
# PORT   le port sur lequel le serveur attend ses clients 

if [ $# -ne 1 ]; then
    echo "usage: $(basename $0) PORT"
    exit -1
fi

PORT="$1"

# Déclaration du tube

FIFO="/tmp/$USER-fifo-$$"

# Il faut détruire le tube quand le serveur termine pour éviter de
# polluer /tmp.  On utilise pour cela une instruction trap pour être sur de
# nettoyer même si le serveur est interrompu par un signal.

function nettoyage() { rm -f "$FIFO"; }
trap nettoyage EXIT

# on crée le tube nommé

[ -e "FIFO" ] || mkfifo "$FIFO"


function accept-loop() {
    while true; do
		interaction < "$FIFO" | netcat -l -p "$PORT" > "$FIFO"
    done
}

# La fonction interaction lit les commandes du client sur entrée standard
# et envoie les réponses sur sa sortie standard. 
#
# 	CMD arg1 arg2 ... argn                   
#                     
# alors elle invoque la fonction :
#                                                                            
#         commande-CMD arg1 arg2 ... argn                                      
#                                                                              
# si elle existe; sinon elle envoie une réponse d'erreur.

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

# Les fonctions implémentant les différentes commandes du serveur

function commande-list() {
	ls=$(ls archives)
	if [ -n "$ls" ]; then
		echo "Les archives présentes sur le serveur sont : $ls"
	else
		echo "Pas d'archives présente sur le serveur"
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
			echo "création impossible, une archive porte déjà ce nom"
		else
			echo "3:5" >> archives/$nomArchive
		fi
	else
		echo "création impossible, pas de nom fourni pour l'archive"
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
   echo "Le serveur ne peut pas interpréter cette commande : $1 $2"
}

# On accepte et traite les connexions

accept-loop
