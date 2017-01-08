#!/bin/bash

declare -r tmppath="/tmp/tmpscan"
declare -r pathToScripts="/opt/scripts"
declare -r scanResolution=600

#declare -r debug="yes"

declare -i c=0	# scan count variable

# splits the scanned image into two and haldle the halves to the processing function 
function procFoto () {
	# removes the extension of the file
	declare arqSemExt="${1%.*}"
	# splits the image into two
	convert $1 \
		-crop 5096x3508 \
		+repage \
		$arqSemExt"_%d.tif"
	# processes the first half
	trataFoto $1 0
	# processes the second half
	trataFoto $1 1
}

# corrects the angles, trims the borders, corrects the levels and converts the result
# to JPEG
function trataFoto () {
declare -r limitLevel=0.97	# level limit to consider an image as empty

	# assembles the filename with c
	declare arqSemExt="${1%.*}""_""$2"

	# determine the level of the image
	declare lvl=$(identify -format "%[fx:mean]\n" "$arqSemExt"".tif")
	# tests if the level is above the limit
	if (( $(bc <<< "$lvl > $limitLevel") )); then
		# if yes, inform the user whether is the upper or lower image
		if [ "$2" -eq "0" ]; then pos="superior"; fi
		if [ "$2" -eq "1" ]; then pos="inferior"; fi
		zenity --info \
			--text="Foto ""$pos"" em branco. Não será processada."
	else
		# if not, processes the image
		
		# window in the bottom of the image to determine its rotation
		declare cutPosX=$((1100))
		declare cutPosY=$((3508/2+1000))
		declare cutSizeX=$((5096-2200))
		declare cutSizeY=$((3508/2-1000))
		
		# identify houghlines from a window in the bottom of the image, to determine
		# its rotation. The image is blurred to remove small artifacts in the
		# borders, then a threshold is applied to transform it into a B&W image. The
		# canny transform is then applied to determine the borders
		convert "$arqSemExt"".tif" \
			-crop "$cutSizeX""x""$cutSizeY""+""$cutPosX""+""$cutPosY" \
			+repage \
			-blur 0x5 -threshold 90% \
			-canny 0x1+10%+30% \
			-hough-lines 50x50+160 \
			"$arqSemExt""hl.mvg"
	
		# Extract houghlines information from .mvg file: 
		# line 0,384.475 5096,117.405  # 203
		# 0    1         2             3 4

		# Declaration of the arrays used in houghlines extraction
		declare -a hl	# elements split per line of the .mvg file
		declare -a hl0	# elements split per spaces of the 3rd line 
		declare -a hlp1	# first point of the line { x , y }
		declare -a hlp2	# second point of the line { x , y }
	
		IFS=$'\r\n' GLOBIGNORE='*' command eval  'hl=($(cat "$arqSemExt""hl.mvg"))'
		IFS=$' ' GLOBIGNORE='*' command eval  'hl0=(${hl[2]})'
		IFS=$',' GLOBIGNORE='*' command eval  'hlp1=(${hl0[1]})'
		IFS=$',' GLOBIGNORE='*' command eval  'hlp2=(${hl0[2]})'
	
		# Calculates the ration between x and y
		a=$(bc <<< "scale=5;-(${hlp2[1]}-${hlp1[1]})/(${hlp2[0]}-${hlp1[0]})")
		# complements with a 0 for the case that the calculation fails
		a="0$a"
	
		# Destroys the arrays
		unset hl
		unset hl0
		unset hlp1
		unset hlp2

		# calculates the angle
		ang=$(bc -l <<< "scale=5;pi=4*a(1);180*a($a)/pi")
	
		# rotates the image to the calculated angle
		convert "$arqSemExt"".tif" \
			-rotate $ang \
			"$arqSemExt""r.tif"
		# automatically trims the white spaces around the image
		$pathToScripts/autotrim -f 65 -c "350,300" -t 25 -b -20 -l 20 -r -20 "$arqSemExt""r.tif" "$arqSemExt""t.tif"
		# adjusts the level of the scanned image. Values determined empirically
		convert "$arqSemExt""t.tif" \
			-level 10%,90%,1.2 \
			"$arqSemExt""aj.tif"
		# calculates the image counter from the scan counter and image index
		local imCount=$(($c*2+$2-2))
		# creates the name of the final .jpg file
		printf -v nomeArq "$szSavePath""_%03d.jpg" $imCount
		# converts the file to JPEG
		convert "$arqSemExt""aj.tif" \
			-quality 90% \
			"$nomeArq"
		# calculates a time from the image counter. Each image adds one second to
		# 12:00"00
		printf -v hora "12%02d.%02d" "$(($imCount/60))" "$(($imCount%60))"
		# converts the date to the format YYYYMMDDhhmm.ss
		dataf=${data:6:4}${data:3:2}${data:0:2}$hora
		# modifies the date of the created file
		touch -m -t "$dataf" "$nomeArq"
	fi
	# if debug is not "yes", removes the temporary files
	if [ "$debug" != "yes" ]; then rm "$arqSemExt"*.*; fi
}

### BEGIN ###

# removes the temporary folder and its contents
rm "$tmppath"/* -R
rmdir "$tmppath"
# (re)create the temporary folder
mkdir "$tmppath"

# sets variable used to check whether a new album is going to be scanned
novoAlbum=0

while [ "$novoAlbum" == 0 ]; do
	# asks the user to enter the album name and location
	szSavePath=$(zenity --file-selection \
		--title="Digite o nome para o novo álbum. As fotos serão nomeadas 'NomeDoAlbum_001.jpg'" \
		--save)
	# asks the user to enter the album date
	data=$(zenity --calendar --text="Selecione a data das fotos")
	# sets variable used to check whether new pictures are going to be scanned
	newScan=0
	# asks the user if (s)he wants to continue the numbering from a previous scan
	c=$(zenity --entry \
		--title="Scan" \
		--text="Digite um número par de 2 a 998 caso deseje continuar um álbum já iniciado")
	# if a number >= 2 is entered, the scan count variable is calculated from it
	if [ "0$c" -ge "0" ]; then let c/=2; else c=0; fi
	while [ "$newScan" == 0 ]; do
		# if the scanned file exists and is not empty
		if [ -s "$f" ]; then
			# processes the image
			procFoto "$f" &
		fi
		# asks the user if (s)he is ready/wants to scan new images
		zenity --question \
			--title="Scan" \
			--text="Deseja escanear novas fotos?"
		# assigns the result to the variable
		newScan=$?
		# if the user chose to scan a new image
		if [ "$newScan" == 0 ]; then
			# create the name of the temporary scanned image from the scan counter
			printf -v f "$tmppath/out%05d.tif" $c
			# scans a new image
			scanimage \
				--format=tiff \
				--mode=Color \
				--resolution $scanResolution \
				| tee \
				# shows a progress bar
				>(zenity --progress \
					--pulsate \
					--auto-close \
					--text "Digitalizando imagem do scanner") \
				# save the scanned image to variable
				>"$f" &
		fi
		# instruction to wait until both the scan and image processing of the previous
		# image finish
		wait
		# if the scanned file is empty
		if [ "$newScan" == 0 ] && [ ! -s "$f" ]; then
			# asks the user if (s)he wants to scan again
			zenity --question \
				--text="Houve uma falha na digitalização. Verifique o scanner.\nPressione \'Sim\' para tentar novamente, ou \'Não\' para terminar o álbum"
			# if yes, restart the loop to scan again, if not, finishes the album
			if [ $? == 0 ]; then continue; else break; fi
		fi
		# increments the scan counter
		c+=1
		# if the counter exceeds 499, finishes the album
		if [ $c -gt 499 ]; then break; fi
	done
	# asks the user if (s)he wants to scan a new album
	zenity --question \
		--title="Scan" \
		--text="Deseja escanear um novo álbum?"
	# assigns the result to variable
	novoAlbum=$?
	# if debug is not "yes", removes the temporary files
	if [ "$debug" != "yes" ]; then rm "$tmppath"/*; fi
done
# if debug is not "yes", removes the temporary files and the temporary folder
if [ "$debug" != "yes" ]; then rmdir "$tmppath"; fi
