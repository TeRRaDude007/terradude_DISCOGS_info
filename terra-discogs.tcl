# ============================================================
# TeRRaDuDe Discogs Music Search Script for Eggdrop
# Command: !music <search query>
#          !music debug <scene name>   (parser test, no API call)
# ============================================================
#
# Requires: Eggdrop 1.9.x, Tcl 8.6+, Tcllib http, json, tls, API key: (https://www.discogs.com/developers)
#
# CHANGELOG
# ---------
# v1.0 - Initial release
# v1.1 - Release details
# v1.2 - Scene release name support
# v1.3 - Various Artists (compilation) support
# v1.4 - Promo/Retail tags and progressive title shortening
# v1.5 - Bracket stripping, extra tags, aggressive title fallback
# v1.6 - Scene name pattern hardening + debug mode
# v1.6.1 - Bugfix: regsub -all -- {--+} (Tcl option parsing)
# v1.6.2 - IRC colours: grey prefix, green content
# v1.6.3 - Two-tone detail line: grey labels, green values
#        - Added music_cmd_label_color config variable
#        - Added color_detail helper proc
#        - Detail parts are now built per-field with their own
#          colour codes, and joined with a neutral separator
#        - Search result lines remain fully green (unchanged)
#
# ============================================================

package require http
package require json
package require tls

http::register https 443 [list ::tls::socket -autoservername true]

# ============================================================
# CONFIGURATION - Adjust these settings
# ============================================================

set discogs_token "YouVeryOwnAPiKEYinHere"
set discogs_user_agent "EggdropDiscogsBot/1.0 +http://example.com"

# IRC colour codes
# \00300 = white, \00314 = grey, \00303 = green, \003 = reset
set music_cmd_prefix "\00300\[\002Music\002\]\003"
set music_cmd_color "\00303"
set music_cmd_label_color "\00314"
set music_cmd_reset "\003"

set music_cmd_error "No results found or an error occurred."
set music_cmd_usage "\002Usage:\002 !music <artist or title>  |  !music debug <scene name>"
set music_cmd_rate_limit "Rate limit reached. Please try again in a minute."
set music_cmd_max_results 4

set music_cmd_detail_separator " | "
set music_cmd_detail_label "Label"
set music_cmd_detail_format "Format"
set music_cmd_detail_country "Country"
set music_cmd_detail_released "Released"
set music_cmd_detail_genre "Genre"
set music_cmd_detail_style "Style"

set scene_source_tags {
    CDS CDM CDA CDEP CD
    VLS VINYL LP
    DVD DVDS DVDA SACD HDDVD BD
    FLASH FM CABLE SAT DVBS DVBC DVBT DAB MD AUD LINE SBD STREAM
    WEB CDR DVDR HDDVDR BDR DAT TAPE BOOTLEG
    PROMO RETAIL ADVANCE
    ONESIDED SIDED WHITE CLEAR COLOURED
    LIMITED EDITION DIRFIX TRACKFIX PROPER RERIP REAL_RERIP
    INCL INCLUDING MIX REMIX RMX REMIXES MIXES DJ_MIX MIXED
}

set scene_numeric_prefixes {2 3 4 5}
set scene_nxm_pattern {2x12|3x12|4x12|2xLP|3xLP|4xLP|2xCD|3xCD|4xCD|2x7|3x7|4x7|2xDVD|3xDVD}

# ============================================================
# END OF CONFIG / DONT EDiTH BELOWS CODE!
# ============================================================

bind pub - !music music_search

proc discogs_api_get {url} {
    global discogs_token discogs_user_agent
    global last_http_code

    set headers [list \
        "User-Agent" $discogs_user_agent \
        "Authorization" "Discogs token=$discogs_token" \
    ]

    if {[catch {
        http::geturl $url -headers $headers -timeout 15000
    } token]} {
        set last_http_code 0
        return ""
    }

    set response_data [http::data $token]
    set last_http_code [http::ncode $token]
    http::cleanup $token

    if {$last_http_code != 200} {
        return ""
    }

    if {[catch {json::json2dict $response_data} json_dict]} {
        return ""
    }

    return $json_dict
}

proc color_detail {label value} {
    global music_cmd_label_color music_cmd_color music_cmd_reset
    return "${music_cmd_label_color}${label}:${music_cmd_reset} ${music_cmd_color}${value}${music_cmd_reset}"
}

proc parse_scene_name {input} {
    global scene_source_tags scene_numeric_prefixes scene_nxm_pattern

    set result [dict create artist "" title ""]
    set cleaned $input

    set cleaned [regsub -all {\([^)]*\)} $cleaned ""]
    set cleaned [regsub -all {\[[^\]]*\]} $cleaned ""]

    set cleaned [regsub -all {_\s*-\s*_} $cleaned "-"]
    set cleaned [regsub -all -- {--+} $cleaned "-"]
    set cleaned [string trim $cleaned]
    set cleaned [string trim $cleaned "_"]

    set match_target [string map {"[" "" "]" "" "(" "" ")" ""} $cleaned]

    set tag_patterns {}
    foreach tag $scene_source_tags {
        lappend tag_patterns [string toupper $tag]
    }
    foreach num $scene_numeric_prefixes {
        foreach tag $scene_source_tags {
            lappend tag_patterns "${num}[string toupper $tag]"
        }
    }

    set tag_patterns [lsort -command {apply {{a b} {expr {[string length $b] - [string length $a]}}}} $tag_patterns]
    set alternation [join $tag_patterns "|"]

    set cut_pos -1
    if {[regexp -nocase -- "-(${alternation})(-|\$)" $match_target -> found_tag]} {
        set cut_pos [string first "-$found_tag" $match_target]
    }
    if {[regexp -nocase -- "-(${scene_nxm_pattern})(-|\$)" $match_target -> nxm_tag]} {
        set nxm_pos [string first "-$nxm_tag" $match_target]
        if {$cut_pos == -1 || $nxm_pos < $cut_pos} {
            set cut_pos $nxm_pos
        }
    }

    if {$cut_pos > 0} {
        set cleaned [string range $match_target 0 [expr {$cut_pos - 1}]]
    } else {
        if {[regexp -- {-WEB-|-[0-9]{4}-} $match_target]} {
            set cleaned [regsub -- {-WEB-.*$|-[0-9]{4}-.*$} $match_target ""]
        }
    }

    set dash_pos [string first "-" $cleaned]
    if {$dash_pos > 0} {
        set artist [string range $cleaned 0 [expr {$dash_pos - 1}]]
        set title  [string range $cleaned [expr {$dash_pos + 1}] end]
    } else {
        set artist ""
        set title  $cleaned
    }

    set artist [string map {"_" " "} $artist]
    set title  [string map {"_" " "} $title]

    set artist [string trim $artist " _-"]
    set title  [string trim $title  " _-"]

    regsub -all {\s+} $artist " " artist
    regsub -all {\s+} $title  " " title
    set artist [string trim $artist]
    set title  [string trim $title]

    set title [regsub -nocase -- {\s+(Incl|Including|Mixed\s+By|Mix(ed)?\s+By\s+DJ)\b.*$} $title ""]
    set title [string trim $title]

    set upper_artist [string toupper $artist]
    if {$upper_artist eq "VA" || $upper_artist eq "V.A." || \
        $upper_artist eq "V.A" || $upper_artist eq "VA." || \
        $upper_artist eq "VARIOUS ARTISTS"} {
        set artist "Various"
    }

    dict set result artist $artist
    dict set result title  $title
    return $result
}

proc looks_like_scene_name {input} {
    global scene_source_tags

    if {[string first "_" $input] >= 0} {
        return 1
    }

    set upper [string toupper $input]
    foreach tag $scene_source_tags {
        if {[string first "-${tag}-" $upper] >= 0} {
            return 1
        }
    }

    if {[regexp -- {^[^-]+-[^-]+-[A-Z0-9]+-[0-9]{4}-[A-Za-z0-9]+$} $input]} {
        return 1
    }

    return 0
}

proc has_search_results {json_dict} {
    if {$json_dict eq ""} { return 0 }
    if {![dict exists $json_dict results]} { return 0 }
    if {[llength [dict get $json_dict results]] == 0} { return 0 }
    return 1
}

proc build_title_variants {title} {
    set variants {}

    set v1 [regsub -- {\s*[\(\[] .*$} $title ""]
    if {$v1 ne $title && $v1 ne "" && $v1 ni $variants} {
        lappend variants $v1
    }

    set v2 [regsub -- {\s+-\s+.*$} $title ""]
    if {$v2 ne $title && $v2 ne "" && $v2 ni $variants} {
        lappend variants $v2
    }

    set words [split $title " "]
    if {[llength $words] > 3} {
        set v3 [join [lrange $words 0 2] " "]
        if {$v3 ne "" && $v3 ni $variants} {
            lappend variants $v3
        }
    }

    set first_dash [string first "-" $title]
    if {$first_dash > 0} {
        set v4 [string range $title 0 [expr {$first_dash - 1}]]
        set v4 [string trim $v4]
        if {$v4 ne "" && $v4 ni $variants} {
            lappend variants $v4
        }
    }

    if {[llength $words] > 2} {
        set v5 [join [lrange $words 0 1] " "]
        if {$v5 ne "" && $v5 ni $variants} {
            lappend variants $v5
        }
    }

    return $variants
}

proc format_scene_debug {input} {
    set is_scene [looks_like_scene_name $input]
    if {!$is_scene} {
        return "Not detected as scene name"
    }
    set parsed [parse_scene_name $input]
    set artist [dict get $parsed artist]
    set title  [dict get $parsed title]
    set variants [build_title_variants $title]

    set out "artist=\[${artist}\] title=\[${title}\]"
    if {[llength $variants] > 0} {
        append out " variants=\[[join $variants { | }]\]"
    }
    return $out
}

proc music_search {nick uhost handle chan text} {
    global music_cmd_prefix music_cmd_color music_cmd_reset
    global music_cmd_error music_cmd_usage
    global music_cmd_rate_limit music_cmd_max_results
    global music_cmd_detail_separator music_cmd_detail_label music_cmd_detail_format
    global music_cmd_detail_country music_cmd_detail_released
    global music_cmd_detail_genre music_cmd_detail_style
    global last_http_code

    set query_text [string trim $text]
    if {$query_text eq ""} {
        putquick "PRIVMSG $chan :${music_cmd_prefix} ${music_cmd_color}${music_cmd_usage}${music_cmd_reset}"
        return
    }

    if {[string tolower [lindex [split $query_text] 0]] eq "debug"} {
        set debug_input [string trim [string range $query_text 5 end]]
        if {$debug_input eq ""} {
            putquick "PRIVMSG $chan :${music_cmd_prefix} ${music_cmd_color}${music_cmd_usage}${music_cmd_reset}"
            return
        }
        set debug_out [format_scene_debug $debug_input]
        putquick "PRIVMSG $chan :${music_cmd_prefix} ${music_cmd_color}DEBUG: ${debug_out}${music_cmd_reset}"
        return
    }

    set is_scene 0
    set parsed_artist ""
    set parsed_title ""
    if {[looks_like_scene_name $query_text]} {
        set is_scene 1
        set parsed [parse_scene_name $query_text]
        set parsed_artist [dict get $parsed artist]
        set parsed_title  [dict get $parsed title]
    }

    set api_url "https://api.discogs.com/database/search"
    set json_dict ""

    if {$is_scene && $parsed_artist ne "" && $parsed_title ne ""} {
        set query_params [http::formatQuery \
            artist $parsed_artist release_title $parsed_title type release]
        set json_dict [discogs_api_get "${api_url}?${query_params}"]

        if {$last_http_code == 429} {
            putquick "PRIVMSG $chan :${music_cmd_prefix} ${music_cmd_color}${music_cmd_rate_limit}${music_cmd_reset}"
            return
        } elseif {$last_http_code == 0} {
            putquick "PRIVMSG $chan :${music_cmd_prefix} ${music_cmd_color}${music_cmd_error} (network error)${music_cmd_reset}"
            return
        }
    } else {
        set query_params [http::formatQuery q $query_text type release]
        set json_dict [discogs_api_get "${api_url}?${query_params}"]

        if {$last_http_code == 429} {
            putquick "PRIVMSG $chan :${music_cmd_prefix} ${music_cmd_color}${music_cmd_rate_limit}${music_cmd_reset}"
            return
        } elseif {$last_http_code == 0} {
            putquick "PRIVMSG $chan :${music_cmd_prefix} ${music_cmd_color}${music_cmd_error} (network error)${music_cmd_reset}"
            return
        }
    }

    if {$is_scene && ![has_search_results $json_dict]} {

        if {[string tolower $parsed_artist] eq "various" && $parsed_title ne ""} {
            set query_params [http::formatQuery release_title $parsed_title type release]
            set json_dict [discogs_api_get "${api_url}?${query_params}"]
            if {$last_http_code == 429} {
                putquick "PRIVMSG $chan :${music_cmd_prefix} ${music_cmd_color}${music_cmd_rate_limit}${music_cmd_reset}"
                return
            }
        }

        if {![has_search_results $json_dict] && $parsed_title ne ""} {
            set norm_title [string map {"," "" "." ""} $parsed_title]
            set norm_title [string trim $norm_title]
            regsub -all {\s+} $norm_title " " norm_title
            if {$norm_title ne ""} {
                set query_params [http::formatQuery release_title $norm_title type release]
                set json_dict [discogs_api_get "${api_url}?${query_params}"]
                if {$last_http_code == 429} {
                    putquick "PRIVMSG $chan :${music_cmd_prefix} ${music_cmd_color}${music_cmd_rate_limit}${music_cmd_reset}"
                    return
                }
            }
        }

        if {![has_search_results $json_dict] && $parsed_title ne ""} {
            set title_variants [build_title_variants $parsed_title]
            foreach variant $title_variants {
                if {$parsed_artist ne ""} {
                    set query_params [http::formatQuery \
                        artist $parsed_artist release_title $variant type release]
                } else {
                    set query_params [http::formatQuery release_title $variant type release]
                }
                set json_dict [discogs_api_get "${api_url}?${query_params}"]
                if {$last_http_code == 429} {
                    putquick "PRIVMSG $chan :${music_cmd_prefix} ${music_cmd_color}${music_cmd_rate_limit}${music_cmd_reset}"
                    return
                }
                if {[has_search_results $json_dict]} { break }

                if {![has_search_results $json_dict]} {
                    set query_params [http::formatQuery release_title $variant type release]
                    set json_dict [discogs_api_get "${api_url}?${query_params}"]
                    if {$last_http_code == 429} {
                        putquick "PRIVMSG $chan :${music_cmd_prefix} ${music_cmd_color}${music_cmd_rate_limit}${music_cmd_reset}"
                        return
                    }
                    if {[has_search_results $json_dict]} { break }
                }
            }
        }

        if {![has_search_results $json_dict]} {
            set query_params [http::formatQuery q $query_text type release]
            set json_dict [discogs_api_get "${api_url}?${query_params}"]
            if {$last_http_code == 429} {
                putquick "PRIVMSG $chan :${music_cmd_prefix} ${music_cmd_color}${music_cmd_rate_limit}${music_cmd_reset}"
                return
            }
        }
    }

    if {![has_search_results $json_dict]} {
        putquick "PRIVMSG $chan :${music_cmd_prefix} ${music_cmd_color}${music_cmd_error}${music_cmd_reset}"
        return
    }

    set results [dict get $json_dict results]
    set display_count [expr {[llength $results] < $music_cmd_max_results ? [llength $results] : $music_cmd_max_results}]
    set first_result [lindex $results 0]

    for {set i 0} {$i < $display_count} {incr i} {
        set item [lindex $results $i]

        set title "Unknown"
        if {[dict exists $item title]} { set title [dict get $item title] }
        set year "?"
        if {[dict exists $item year]} { set year [dict get $item year] }
        set url "https://www.discogs.com"
        if {[dict exists $item uri]} { append url [dict get $item uri] }

        putquick "PRIVMSG $chan :${music_cmd_prefix} ${music_cmd_color}${title} (${year}) - ${url}${music_cmd_reset}"

        if {$i < [expr {$display_count - 1}]} { after 500 }
    }

    if {![dict exists $first_result id]} { return }
    set release_id [dict get $first_result id]

    set detail_url "https://api.discogs.com/releases/${release_id}"
    set detail_dict [discogs_api_get $detail_url]

    if {$detail_dict eq ""} { return }

    set parts {}

    if {[dict exists $detail_dict labels]} {
        set label_parts {}
        foreach lbl [dict get $detail_dict labels] {
            set lname [expr {[dict exists $lbl name] ? [dict get $lbl name] : ""}]
            set lcatno [expr {[dict exists $lbl catno] ? [dict get $lbl catno] : ""}]
            if {$lcatno ne ""} {
                lappend label_parts "${lname} – ${lcatno}"
            } elseif {$lname ne ""} {
                lappend label_parts $lname
            }
        }
        if {[llength $label_parts] > 0} {
            lappend parts [color_detail $music_cmd_detail_label [join $label_parts {, }]]
        }
    }

    if {[dict exists $detail_dict formats]} {
        set fmt_parts {}
        foreach fmt [dict get $detail_dict formats] {
            set fname [expr {[dict exists $fmt name] ? [dict get $fmt name] : ""}]
            set fdesc {}
            if {[dict exists $fmt descriptions]} {
                set fdesc [join [dict get $fmt descriptions] {, }]
            }
            if {$fdesc ne ""} {
                lappend fmt_parts "${fname}, ${fdesc}"
            } elseif {$fname ne ""} {
                lappend fmt_parts $fname
            }
        }
        if {[llength $fmt_parts] > 0} {
            lappend parts [color_detail $music_cmd_detail_format [join $fmt_parts {; }]]
        }
    }

    if {[dict exists $detail_dict country]} {
        lappend parts [color_detail $music_cmd_detail_country [dict get $detail_dict country]]
    }
    if {[dict exists $detail_dict released_formatted]} {
        lappend parts [color_detail $music_cmd_detail_released [dict get $detail_dict released_formatted]]
    } elseif {[dict exists $detail_dict released]} {
        lappend parts [color_detail $music_cmd_detail_released [dict get $detail_dict released]]
    }
    if {[dict exists $detail_dict genres]} {
        set genres [join [dict get $detail_dict genres] {, }]
        if {$genres ne ""} {
            lappend parts [color_detail $music_cmd_detail_genre $genres]
        }
    }
    if {[dict exists $detail_dict styles]} {
        set styles [join [dict get $detail_dict styles] {, }]
        if {$styles ne ""} {
            lappend parts [color_detail $music_cmd_detail_style $styles]
        }
    }

    if {[llength $parts] > 0} {
        set body [join $parts $music_cmd_detail_separator]
        putquick "PRIVMSG $chan :${music_cmd_prefix} ${body}"
    }
}

putlog "TeRRaDuDe Discogs Music Search script v1.6.3 loaded."
