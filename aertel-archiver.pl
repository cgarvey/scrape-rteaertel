#!/usr/bin/perl
use strict;

#  Copyright 2012 Cathal Garvey. http://cgarvey.ie/
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

use strict;

my( $VERSION ) = "1.0";
my( $MAX_PAGE ) = 999; # Maximum Aertel teletext page number is normally 999 (even if there is no content up that high). Set to a low page number for testing (e.g. 101)

use LWP::UserAgent;
use HTTP::Request::Common;

$| = 1;

# Set up HTTP client, with a reasonable looking User Agent
my( $agent ) = new LWP::UserAgent;
$agent->agent( "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; .NET CLR 1.0.3705)" );

# Create any missing folders
if( !-d( "./images" ) ) { mkdir "./images" or die "Can't make images/ directory\n"; }
if( !-d( "./html" ) ) { mkdir "./html" or die "Can't make html/ directory\n"; }
if( !-d( "./render" ) ) { mkdir "./render" or die "Can't make render/ directory\n"; }

if( lc( $ARGV[0] ) eq "archive" || lc( $ARGV[0] ) eq "a" ) {
	# Archive mode - download Aertel content from RTE.ie and store teletext image (and associated image map data) locally.
	print "\nStarting.\n";

	if( !-r( "template/logo.gif" ) ) {
		# If the RTE Aertel logo isn't already archived, do it now. It's used in the default rendering template.
		print "Getting logo... ";
		my( $binLogo ) = &get( "", "http://www.rte.ie/aertel/images/logo.gif" );
		open( F, ">:raw", "template/logo.gif" ) or die "Can't open logo.gif for writing\n";
		print F $binLogo;
		close( F );
		print "done.\n";
	}

	# For all 999 pages (need to iterate through them because some pages are orphaned, so we can't rely on prev/next page links to determine what pages exist).
	for( my $i = 100; $i <= $MAX_PAGE; $i++ ) { # Outer loop for Pages
		for( my $j = 1; $j < 99; $j++ ) { # Inner loop for Sub-pages
			my( $page ) = $i. "-" . sprintf( "%02d", $j );
			print "Getting $page ";
			# Attempt to retrive the page HTML
			my( $s ) = &get( $page );
	
			if( $s =~ /(<map name="$page">.*<\/map>)/s ) {
				# Looks like a valid teletext page, store the image and image map locally.
				my( $sMap ) = $1;
				$sMap =~ s/^/\t\t\t/gm;
				open( F, ">./html/$page.html" ) or die "Can't open $page.html for writing.\n";
				print F "\n\n";
				print F "\t\t\t<!-- Begin Scraped Data (Retrieved " . localtime() . ") -->\n";
				print F $sMap . "\n";
				print F "\t\t\t<img src=\"../images/$page.gif\" title=\"Aertel page $page\" usemap=\"#$page\" />\n";
				print F "\t\t\t<!-- End Scraped Data -->\n";
				print F "\n\n";
				close( F );
				print "[Map] ";
			
				if( $s =~ /<img src="images\/$page\.gif".*usemap="\#$page".*/ ) {
					# Retrieve, and store locally, the teletext page image.
					my( $binLogo ) = &get( "", "http://www.rte.ie/aertel/images/$page.gif" );
					open( F, ">:raw", "images/$page.gif" ) or die "Can't open images/$page.gif for writing\n";
					print F $binLogo;
					close( F );
					print "[Img] ";
	
					if( $s =~ /<a href="([0-9-]*).html">Next SubPage/ ) {
						# If we have a 'Next SubPage' link, then continue on to next sub page (unless there's an out of sequence sub-page)
						my( $sNext ) = $i . "-" . sprintf( "%02d", ( $j + 1 ) );
						if( $sNext ne $1 ) { print "[OutOfSequenceSubPage Got:$1 Expected:$sNext] "; $j = 200; }
						else { print "[Sub] "; }
					}
					else {
						# No Next Subpage, so bail out of the inner loop
						$j = 200;
					}
				}
			}
			else {
				# Not a valid teletext page (most likely a 404 if we were bothered to check), so skip.
				print "[CAN NOT PARSE] ";
				$j = 200;
			}
			print "\n";
		}
	}

	print "\nFinished.\n";
}
elsif( lc( $ARGV[0] ) eq "render" || lc( $ARGV[0] ) eq "r" ) {
	# Render mode - render all locally saved HTML files using the template HTML (template/page.html) and store in the render/ folder leaving the archived data untouched.
	print "\nReading archived HTML... ";
	opendir( D, "./html" );
	my( @dir ) = readdir( D );
	closedir( D );
	print "done. (" . ( 1 + $#dir - 2 ) . " files).\n"; # -2 to ignore current/parent directory nodes

	print "Reading Template... "; # Read the entire template in to memory
	open( F, "./template/page.html" ) or die "Couldn't read template/page.html\n";
	my( $template ) = "";
	my( $line ) = "";
	while( defined( $line = <F> ) ) {
		$template .= $line;
	}
	close( F );
	print "done.\n";

	print "Processing HTML files... 0000"; # Progress indication
	my( $i ) = 0;
	my( $f );
	foreach $f( @dir ) {
		if( $f =~ /.html$/ ) {
			$i += 1;
			print "\b\b\b\b" . sprintf( "%04d", $i );

			my( $page ) = "";
			open( F, "./html/$f" ) or die "Could not open html/$f archive HTML.\n";
			while( defined( $line = <F> ) ) {
				$page .= $line;
			}
			close( F );

			# Get current page, and sub-page numbers. Use these to determine if we have previous/next sub pages for this page.
			my( $pagenum ) = 0;
			my( $subpagenum ) = 0;
			if( $f =~ /([0-9]*)-([0-9]*)\.html/ ) {
				$pagenum = ( 0 + $1 );
				$subpagenum = ( 0 + $2 );
			}
			# Check for Prev sub page
			my( $prevsubpage ) = 0;
			if( $subpagenum > 1 ) {
				if( -r( "html/" . sprintf( "%03d-%02d", $pagenum, ( $subpagenum - 1 ) ) . ".html" ) ) { $prevsubpage = ( $subpagenum - 1 ); }
			}
			# Check for Next sub page
			my( $nextsubpage) = 0;
			if( -r( "html/" . sprintf( "%03d-%02d", $pagenum, ( $subpagenum + 1 ) ) . ".html" ) ) { $nextsubpage = ( $subpagenum + 1 ); }

			# Template substitution
			my( $render ) = $template; # start with template
			my( $pagenumstr ) = sprintf( "%03d (%02d)", $pagenum, $subpagenum );
			$render =~ s/##PAGE##/$pagenumstr/g; #current page number
			if( $prevsubpage > 0 ) { #previous sub page number/link
				my( $prevsubpagestr ) = sprintf( "%03d-%02d", $pagenum, $prevsubpage );
				$render =~ s/##PREVSUBPAGENUM##/$prevsubpagestr/g;
				$render =~ s/##PREVSUBPAGE(.*)##/$1/g;
			}
			else {
				$render =~ s/##PREVSUBPAGENUM##//g;
				$render =~ s/##PREVSUBPAGE(.*)##/&nbsp;/g;
			}
			if( $nextsubpage > 0 ) { #next sub page number/link
				my( $nextsubpagestr ) = sprintf( "%03d-%02d", $pagenum, $nextsubpage );
				$render =~ s/##NEXTSUBPAGENUM##/$nextsubpagestr/g;
				$render =~ s/##NEXTSUBPAGE(.*)##/$1/g;
			}
			else {
				$render =~ s/##NEXTSUBPAGENUM##//g;
				$render =~ s/##NEXTSUBPAGE(.*)##/&nbsp;/g;
			}

			$render =~ s/##CONTENT##/$page/g; # Finally, the content from the archived HTML (<image> and <map> HTML).

			open( F, ">./render/$f" ) or die "Could not open render/$f for writing rendered HTML.\n";
			print F $render;
			close( F );
		}
	}
	print "\b\b\b\b" . $i ." files processed.\n";
}
else {
	print "\nUsage: $0 <command>\n\n";
	print "Where <command> is either:\n";
	print "    'archive' - Retrieve Aertel content from RTE.ie, and archive locally.\n";
	print "    'render'  - Generate rendered pages (using template.html) from locally\n";
	print "                archived Aertel pages.\n";
	print "\n";
}


exit;

sub get() {
	# Simpe HTTP GET request
	my( $page ) = $_[0];
	my( $url ) = $_[1];

	# If no URL is provided, assume it's a page request, for which we know the URL.
	if( $url eq "" ) { $url = "http://www.rte.ie/aertel/$page.html"; }

	my( $req ) = new HTTP::Request( "GET", $url );
	$req->content_type( "application/x-www-form-urlencoded" );
	$req->header( "Referer" => "http://www.rte.ie/aertel/101-01.html" ); # Just to have some dummy refer to look a bit more reasonably in RTE's logs!
	my( $resp ) = $agent->request( $req );

	return $resp->content();
}

