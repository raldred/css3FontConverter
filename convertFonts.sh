#!/bin/bash

SCRIPT_DIR=$(echo $0 | sed "s/convertfonts.sh//")
OUTPUT_DIR=${1%/*}

SFNT2WOFF=$(which sfnt2woff 2> /dev/null)
TTF2EOT=$(which ttf2eot 2> /dev/null)
FONTFORGE=$(which fontforge 2> /dev/null)
FONDU=$(which fondu 2> /dev/null)

IFS=$(echo -en "\n\b")

toTTF () {
	$FONTFORGE -script $SCRIPT_DIR/2ttf.pe $i $2 2> /dev/null
}

toEOT () {
	$TTF2EOT $1 > $2.eot
}

toSVG() {
	$FONTFORGE -script $SCRIPT_DIR/2svg.pe $i $2 2> /dev/null
}

toWOFF () {
	$SFNT2WOFF $1
	if [[ -f $ORIG_STUB.woff ]]; then
		mv $ORIG_STUB.woff $2.woff
	fi
}

getFontName () {
	$FONTFORGE -script $SCRIPT_DIR/getFontName.pe $1 2> /dev/null | tr ' ' '-'
}

getFontFamily () {
	$FONTFORGE -script $SCRIPT_DIR/getFontFamily.pe $1 2> /dev/null | tr ' ' '-'
}

getFontWeight () {
	$FONTFORGE -script $SCRIPT_DIR/getFontWeight.pe $1 2> /dev/null
}

getSVGID () {
	grep "id=" $1 | tr ' ' '
' | grep ^id | awk -F'"' '{print $2}'
}

if [[ "$#" == "0" ]]
then
	echo "Usage: $0 <font list>" 1>&2
	exit 1
fi

# .. check to make sure all packages are installed
for i in sfnt2woff ttf2eot fontforge
do
	which $i > /dev/null 2> /dev/null
	if [[ "$?" != "0" ]]
	then
		echo "Error: Package $i is not installed.  Bailing" 1>&2
		exit 2
	fi
done

for i in $*
do
	#.. check to see if it's a TrueType font
	file "$i" | grep "TrueType" > /dev/null
	IS_TTF="$?"

	file "$i" | grep "OpenType" > /dev/null
	IS_OTF="$?"

	file "$i" | grep "empty" > /dev/null
	cat $i/..namedfork/rsrc > "$i.dfont"
	if [[ -s "$i.dfont" ]]; then
		f_out=$($FONDU -force -show "$i.dfont" 2>&1 | awk '{print $2}' )
		mv $f_out $i.pfb
		rm "$i.dfont"
		file "$i.pfb" | grep "PostScript Type 1" > /dev/null
		IS_PS1="$?"
		i=$i.pfb
	fi
	if [[ -f "$i.dfont" ]]; then rm "$i.dfont"; fi


	if [[ "$IS_OTF" = 0 || "$IS_TTF" = 0 || "$IS_PS1" = 0 ]]
	then
		ORIG_FILE=$i
		ORIG_STUB=$(echo $i | sed "s/\.[tT][tT][fF]$//" | sed "s/\.[oO][tT][fF]$//" | sed "s/\.[pP][fF][bB]$//" | sed -e 's/^[ \t]*//')
	
		NEW_FILE=$(echo $i | sed "s/ /-/g")
		NEW_STUB=$(echo $NEW_FILE |	sed "s/\.[tT][tT][fF]$//" | sed "s/\.[oO][tT][fF]$//" | sed "s/\.[pP][fF][bB]$//")

		FONT_NAME=$(echo $(getFontName $ORIG_FILE) | sed -e 's/^[ \t]*//' | sed "s/-$//")
		FONT_FAMILY=$(echo $(getFontFamily $ORIG_FILE) | sed -e 's/^[ \t]*//' | sed "s/-$//")
		FONT_WEIGHT=$(echo $(getFontWeight $ORIG_FILE) | sed -e 's/^[ \t]*//')

		echo $FONT_FAMILY

		echo "Converting $i - $FONT_FAMILY ($FONT_WEIGHT) for fontface ..."

		OUT_DIR="$FONT_FAMILY-webfont"
		if [[ ! -d $OUT_DIR ]]; then
			mkdir $OUT_DIR
		fi

		if [[ "$IS_PS1" = "0" || "$IS_OTF" = "0" ]] && [[ ! -f $NEW_STUB.ttf ]]; then
			printf "  TTF... "
			toTTF $i $OUT_DIR/$NEW_STUB
			if [[ "$?" == "0" ]]; then
				printf "OK ($OUT_DIR/$NEW_STUB.ttf)\n"
				i=$OUT_DIR/$NEW_STUB.ttf
			else
				printf "FAILED\n"
				exit
			fi

		fi

		printf "  EOT..."
		if [[ ! -f $NEW_STUB.eot ]]; then
			
			toEOT $i $OUT_DIR/$NEW_STUB
			if [[ "$?" == "0" ]]; then printf "OK ($OUT_DIR/$NEW_STUB)\n"; else printf "FAILED\n"; exit; fi
		else 
			printf "Skipped\n"
		fi
	
		printf "  SVG... "
		if [[ ! -f $NEW_STUB.svg ]]; then
			toSVG $i $OUT_DIR/$NEW_STUB
			if [[ "$?" == "0" ]]; then printf "OK ($OUT_DIR/$NEW_STUB)\n"; else printf "FAILED\n"; exit; fi
		else 
			printf "Skipped\n"
		fi
	
		printf "  WOFF... "
		if [[ ! -f $NEW_STUB.woff ]]; then
			toWOFF $i $OUT_DIR/$NEW_STUB
			if [[ "$?" == "0" ]]; then printf "OK ($OUT_DIR/$NEW_STUB)\n"; else printf "FAILED\n"; exit; fi
		else 
			printf "Skipped\n"
		fi

		SVG_ID=$(getSVGID $OUT_DIR/$NEW_STUB.svg)


		printf "Adding $FONT_NAME to stylesheet... "
		echo "@font-face {
	font-family: '$FONT_NAME';
	src: url('$OUT_DIR/$NEW_STUB.eot') format('eot');
	src: url('$OUT_DIR/$NEW_STUB.svg#$SVG_ID') format('svg'),
		 url('$OUT_DIR/$NEW_STUB.eot?#ieFix') format('eot'),
		 url('$OUT_DIR/$NEW_STUB.woff') format('woff'),
	     url('$OUT_DIR/$NEW_STUB.ttf') format('truetype');" >> stylesheet.css
	    if [[ $FONT_WEIGHT == "Bold" ]]; then
	    	echo "	font-weight: bold;" >> stylesheet.css
	    fi
	    echo "}" >> $NEW_STUB.css
		printf "OK\n\n"


		# cleanup dfont if we had one		
		if [[ -f "$ORIG_STUB.pfb" ]]; then rm "$ORIG_STUB.pfb"; fi

	else
		echo "File $i is not a TrueType or OpenType font. Skipping"
	fi
done

