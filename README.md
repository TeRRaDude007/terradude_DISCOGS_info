DISCOGS MUSIC SEARCH SCRIPT FOR EGGDROP

Version:    1.6.3
Language:   TCL
API:        Discogs API v2 (https://www.discogs.com/developers)
Author:     TeRRaDuDe Custom build for Eggdrop IRC bots

OVERVIEW

This script adds a !music command to your Eggdrop IRC bot. It searches the
Discogs music database and returns release information directly in the
channel - including title, year, URL, label, format, country, release date,
genre and style.

It is specifically designed to handle scene release names - the standardised
file naming used by release groups (e.g.
Madonna-Papa_Dont_Preach-(HTFUNK021)-Onesided_Bootleg_Vinyl-2008-MTC) - and
intelligently extracts the artist and title before querying Discogs.

COMMANDS

!music <search query>
----------------------

Searches Discogs for the given query and returns up to 3 results
(configurable), followed by detailed release information for the first match.

Examples:

    !music Nirvana Nevermind
    !music Madonna-Frozen__Digital_Poison_Remix-Promo_Vinyl-2005-GRPNAME
    !music VA-Techno_Underground_Vol._10-WEB-2026-GRPNAME
    !music Madonna-Papa_Dont_Preach-(HTFUNK021)-Onesided_Bootleg_Vinyl-2008-GRPNAME

Output example (in-channel):

    [Music] Madonna - Papa Don't Preach (1986) - https://www.discogs.com/release/1185557-Madonna-Papa-Dont-Preach
    [Music] Label: Sire - 92 8660-7 | Format: Vinyl, 7", 45 RPM, Single | Country: Italy | Released: 1986 | Genre: Electronic | Style: Synth-pop


!music debug <scene name>
--------------------------

Tests the scene-name parser WITHOUT making any API calls. 
Useful for verifying how a release name will be interpreted before searching.

Example:

    !music debug Madonna-Papa_Dont_Preach-(HTFUNK021)-Onesided_Bootleg_Vinyl-2008-GRPNAME

Output:

    [Music] DEBUG: artist=[Madonna] title=[Papa Dont Preach] variants=[Papa Dont]

This shows:
  - The extracted artist name
  - The extracted release title
  - The fallback title variants the script will try if the primary search fails


INSTALLATION

  1. Save the script as discogs.tcl in your Eggdrop scripts/ directory.
  2. Add to your bot's .conf:

         source scripts/discogs.tcl

  3. Edit the configuration section with your token and User-Agent.
  4. Restart the bot or .rehash the config.
  5. Test in-channel:

         !music debug Madonna-Frozen__Digital_Poison_Remix-Promo_Vinyl-2005-MNS
         !music Nirvana Nevermind

KNOWN LIMITATIONS

  1. Rate limit
     Discogs allows 60 requests/minute for authenticated requests. A
     scene-name search may use 2-6 requests (primary + fallbacks + detail
     call), so heavy use can hit the limit.

  2. Bracketed real titles
     Because the parser strips everything between brackets, a release whose
     real title contains parentheses (e.g. "(What's The Story) Morning
     Glory?") may lose part of its title. The fallback chain usually recovers
     it.

  3. Untagged scene names
     Release names without a source tag are split on the first "-", which may
     not always be correct (e.g. artist names containing a dash).

  4. HAVE/WANT counts
     The script doesn't display marketplace or community statistics, though
     the API supports it.

  5. Images
     The script doesn't post cover art URLs. Image requests require OAuth,
     which is out of scope for this script.

  6. Non-English labels
     The detail labels are English by default; translate them in the config
     if desired.

  7. Discogs API changes
     This script targets API v2 as documented in 2024. Future API changes may
     require updates.


TROUBLESHOOTING

"No results found or an error occurred."
  - Check that your token is valid and pasted correctly.
  - Check that your User-Agent is unique (not the example).
  - Check the bot log for TCL errors.
  - Try !music debug <scene name> to see what the parser produces.
  - Try the parsed artist + title manually on discogs.com.

"Rate limit reached"
  - You've made too many requests in one minute. Wait 60 seconds.
  - Multiple users searching simultaneously can exhaust the limit quickly.

TCL error "bad option ..."
  - Likely a pattern beginning with "-" that isn't preceded by "--". Check the
    line number in the error and add "--" before the pattern.

HTTPS fails ("network error")
  - Check that tls is installed: package require tls
  - Check that http::register https 443 [list ::tls::socket -autoservername
    true] is present in the script.
  - Older TCL versions may need -tls1 1 instead of -autoservername true.

JSON parse error
  - Check that json is installed: package require json
  - On some systems the package is called tcllib or tcl-json.


This script is provided as-is for personal use. The Discogs API is subject to
Discogs' API Terms of Use (https://www.discogs.com/developers/#terms). Please
ensure your bot respects the rate limits and identifies itself with a unique
User-Agent.
