package Parse::WBXML;
# ABSTRACT: Support for WBXML as defined by the Open Mobile Alliance specs
use strict;
use warnings;
use parent qw(Mixin::Event::Dispatch);

use I18N::Charset qw(mib_to_charset_name);
use Encode ();

our $VERSION = '0.001';

=head1 NAME

Parse::WBXML - event-driven support for the generation and parsing of WBXML documents

=head1 VERSION

version 0.001

=head1 SYNOPSIS

 use Parse::WBXML;
 my $wbxml = Parse::WBXML->new;
 $wbxml->add_handler_for_event(
   start_element => sub {
     my ($self, $el) = @_;
     $self;
   },
   characters => sub {
     my ($self, $data) = @_;
     $self;
   },
   end_element => sub {
     my ($self, $el) = @_;
     $self;
   },
 );
 $wbxml->parse("wbxml data");

=head1 DESCRIPTION

WARNING: this is an early alpha release, if you want WBXML support then please try
the other modules in L</SEE ALSO> first. The current API may change before the 1.0
release.

Provides a pure-Perl implementation for the WBXML compressed XML format.
Slower and less efficient than the libwbxml2-based alternatives (L</SEE ALSO>),
but supports streaming SAX-like parsing.

This may be of some use in low-bandwidth situations where you want data as soon
as available from the stream, or in cases where the document is damaged and you
want to recover as much data as possible, or if you just don't have libwbxml2
available.

=head1 METHODS

=cut

# From WAP-192-WBXML-20010725-a table 4, "Global tokens"
use constant {
	TOKEN_SWITCH_PAGE	=> 0x00,
	TOKEN_END		=> 0x01,
	TOKEN_ENTITY		=> 0x02,
	TOKEN_STR_I		=> 0x03,
	TOKEN_LITERAL		=> 0x04,
	TOKEN_EXT_I_0		=> 0x40,
	TOKEN_EXT_I_1		=> 0x41,
	TOKEN_EXT_I_2		=> 0x42,
	TOKEN_PI		=> 0x43,
	TOKEN_LITERAL_C		=> 0x44,
	TOKEN_EXT_T_0		=> 0x80,
	TOKEN_EXT_T_1		=> 0x81,
	TOKEN_EXT_T_2		=> 0x82,
	TOKEN_STR_T		=> 0x83,
	TOKEN_LITERAL_A		=> 0x84,
	TOKEN_EXT_0		=> 0xC0,
	TOKEN_EXT_1		=> 0xC1,
	TOKEN_EXT_2		=> 0xC2,
	TOKEN_OPAQUE		=> 0xC3,
	TOKEN_LITERAL_AC	=> 0xC4,
};

# From WAP-192-WBXML-20010725-a table 5 ("Public Identifiers")
my %public_id = (
	0 => 'String table index',
	1 => 'Unknown',
	2 => "-//WAPFORUM//DTD WML 1.0//EN",
	3 => "-//WAPFORUM//DTD WTA 1.0//EN",
	4 => "-//WAPFORUM//DTD WML 1.1//EN",
	5 => "-//WAPFORUM//DTD SI 1.0//EN",
	6 => "-//WAPFORUM//DTD SL 1.0//EN",
	7 => "-//WAPFORUM//DTD CO 1.0//EN",
	8 => "-//WAPFORUM//DTD CHANNEL 1.1//EN",
	9 => "-//WAPFORUM//DTD WML 1.2//EN",
	10 => "-//WAPFORUM//DTD WML 1.3//EN",
	11 => "-//WAPFORUM//DTD PROV 1.0//EN",
	12 => "-//WAPFORUM//DTD WTA-WML 1.2//EN",
	13 => "-//WAPFORUM//DTD CHANNEL 1.2//EN",
);

# From a myriad of OMA specs, and the wbrules.xml file in WAP-wbxml, haven't
# found a single comprehensive list (although the latter comes close).
my %ns = (
	"-//WAPFORUM//DTD SI 1.0//EN" => {
		tag => {
			0 => {
				5 => q{si},
				6 => q{indication},
				7 => q{info},
				8 => q{item},
			},
		},
		attrstart => {
			0 => {
				5 => { name => q{action}, prefix => q{signal-none} },
				6 => { name => q{action}, prefix => q{signal-low} },
				7 => { name => q{action}, prefix => q{signal-medium} },
				8 => { name => q{action}, prefix => q{signal-high} },
				9 => { name => q{action}, prefix => q{delete} },
				10 => { name => q{created}, prefix => q{} },
				11 => { name => q{href}, prefix => q{} },
				12 => { name => q{href}, prefix => q{http://} },
				13 => { name => q{href}, prefix => q{http://www.} },
				14 => { name => q{href}, prefix => q{https://} },
				15 => { name => q{href}, prefix => q{https://www.} },
				16 => { name => q{si-expires}, prefix => q{} },
				17 => { name => q{si-id}, prefix => q{} },
				18 => { name => q{class}, prefix => q{} },
			},
		},
		attrvalue => {
			0 => {
				133 => q{.com/},
				134 => q{.edu/},
				135 => q{.net/},
				136 => q{.org/},
			},
		},
	},
	"-//WAPFORUM//DTD SL 1.0//EN" => {
		tag => {
			0 => {
				5 => q{sl},
			},
		},
		attrstart => {
			0 => {
				5 => { name => q{action}, prefix => q{execute-low} },
				6 => { name => q{action}, prefix => q{execute-high} },
				7 => { name => q{action}, prefix => q{cache} },
				8 => { name => q{href}, prefix => q{} },
				9 => { name => q{href}, prefix => q{http://} },
				10 => { name => q{href}, prefix => q{http://www.} },
				11 => { name => q{href}, prefix => q{https://} },
				12 => { name => q{href}, prefix => q{https://www.} },
			},
		},
		attrvalue => {
			0 => {
				133 => q{.com/},
				134 => q{.edu/},
				135 => q{.net/},
				136 => q{.org/},
			},
		},
	},
	"-//WAPFORUM//DTD CO 1.0//EN" => {
		tag => {
			0 => {
				5 => q{co},
				6 => q{invalidate-object},
				7 => q{invalidate-service},
			},
		},
		attrstart => {
			0 => {
				5 => { name => q{uri}, prefix => q{} },
				6 => { name => q{uri}, prefix => q{http://} },
				7 => { name => q{uri}, prefix => q{http://www.} },
				8 => { name => q{uri}, prefix => q{https://} },
				9 => { name => q{uri}, prefix => q{https://www.} },
			},
		},
		attrvalue => {
			0 => {
				133 => q{.com/},
				134 => q{.edu/},
				135 => q{.net/},
				136 => q{.org/},
			},
		},
	},
	"-//WAPFORUM//DTD CHANNEL 1.2//EN" => {
		tag => {
			0 => {
				5 => q{channel},
				6 => q{title},
				7 => q{abstract},
				8 => q{resource},
			},
		},
		attrstart => {
			0 => {
				5 => { name => q{maxspace}, prefix => q{} },
				6 => { name => q{base}, prefix => q{} },
				7 => { name => q{href}, prefix => q{} },
				8 => { name => q{href}, prefix => q{http://} },
				9 => { name => q{href}, prefix => q{https://} },
				10 => { name => q{lastmod}, prefix => q{} },
				11 => { name => q{etag}, prefix => q{} },
				12 => { name => q{md5}, prefix => q{} },
				13 => { name => q{success}, prefix => q{} },
				14 => { name => q{success}, prefix => q{http://} },
				15 => { name => q{success}, prefix => q{https://} },
				16 => { name => q{failure}, prefix => q{} },
				17 => { name => q{failure}, prefix => q{http://} },
				18 => { name => q{failure}, prefix => q{https://} },
				19 => { name => q{eventid}, prefix => q{} },
				20 => { name => q{eventid}, prefix => q{wtaev-} },
				21 => { name => q{channelid}, prefix => q{} },
				22 => { name => q{useraccessible}, prefix => q{} },
			},
		},
		attrvalue => {
		},
	},
	"-//WAPFORUM//DTD CHANNEL 1.1//EN" => {
		tag => {
			0 => {
				5 => q{channel},
				6 => q{title},
				7 => q{abstract},
				8 => q{resource},
			},
		},
		attrstart => {
			0 => {
				5 => { name => q{maxspace}, prefix => q{} },
				6 => { name => q{base}, prefix => q{} },
				7 => { name => q{href}, prefix => q{} },
				8 => { name => q{href}, prefix => q{http://} },
				9 => { name => q{href}, prefix => q{https://} },
				10 => { name => q{lastmod}, prefix => q{} },
				11 => { name => q{etag}, prefix => q{} },
				12 => { name => q{md5}, prefix => q{} },
				13 => { name => q{success}, prefix => q{} },
				14 => { name => q{success}, prefix => q{http://} },
				15 => { name => q{success}, prefix => q{https://} },
				16 => { name => q{failure}, prefix => q{} },
				17 => { name => q{failure}, prefix => q{http://} },
				18 => { name => q{failure}, prefix => q{https://} },
				19 => { name => q{EventId}, prefix => q{} },
			},
		},
		attrvalue => {
		},
	},
	"-//WAPFORUM//DTD WML 1.3//EN" => {
		tag => {
			0 => {
				27 => q{pre},
				28 => q{a},
				29 => q{td},
				30 => q{tr},
				31 => q{table},
				32 => q{p},
				33 => q{postfield},
				34 => q{anchor},
				35 => q{access},
				36 => q{b},
				37 => q{big},
				38 => q{br},
				39 => q{card},
				40 => q{do},
				41 => q{em},
				42 => q{fieldset},
				43 => q{go},
				44 => q{head},
				45 => q{i},
				46 => q{img},
				47 => q{input},
				48 => q{meta},
				49 => q{noop},
				50 => q{prev},
				51 => q{onevent},
				52 => q{optgroup},
				53 => q{option},
				54 => q{refresh},
				55 => q{select},
				56 => q{small},
				57 => q{strong},
				59 => q{template},
				60 => q{timer},
				61 => q{u},
				62 => q{setvar},
				63 => q{wml},
			},
		},
		attrstart => {
			0 => {
				5 => { name => q{accept-charset}, prefix => q{} },
				6 => { name => q{align}, prefix => q{bottom} },
				7 => { name => q{align}, prefix => q{center} },
				8 => { name => q{align}, prefix => q{left} },
				9 => { name => q{align}, prefix => q{middle} },
				10 => { name => q{align}, prefix => q{right} },
				11 => { name => q{align}, prefix => q{top} },
				12 => { name => q{alt}, prefix => q{} },
				13 => { name => q{content}, prefix => q{} },
				15 => { name => q{domain}, prefix => q{} },
				16 => { name => q{emptyok}, prefix => q{false} },
				17 => { name => q{emptyok}, prefix => q{true} },
				18 => { name => q{format}, prefix => q{} },
				19 => { name => q{height}, prefix => q{} },
				20 => { name => q{hspace}, prefix => q{} },
				21 => { name => q{ivalue}, prefix => q{} },
				22 => { name => q{iname}, prefix => q{} },
				24 => { name => q{label}, prefix => q{} },
				25 => { name => q{localsrc}, prefix => q{} },
				26 => { name => q{maxlength}, prefix => q{} },
				27 => { name => q{method}, prefix => q{get} },
				28 => { name => q{method}, prefix => q{post} },
				29 => { name => q{mode}, prefix => q{nowrap} },
				30 => { name => q{mode}, prefix => q{wrap} },
				31 => { name => q{multiple}, prefix => q{false} },
				32 => { name => q{multiple}, prefix => q{true} },
				33 => { name => q{name}, prefix => q{} },
				34 => { name => q{newcontext}, prefix => q{false} },
				35 => { name => q{newcontext}, prefix => q{true} },
				36 => { name => q{onpick}, prefix => q{} },
				37 => { name => q{onenterbackward}, prefix => q{} },
				38 => { name => q{onenterforward}, prefix => q{} },
				39 => { name => q{ontimer}, prefix => q{} },
				40 => { name => q{optional}, prefix => q{false} },
				41 => { name => q{optional}, prefix => q{true} },
				42 => { name => q{path}, prefix => q{} },
				46 => { name => q{scheme}, prefix => q{} },
				47 => { name => q{sendreferer}, prefix => q{false} },
				48 => { name => q{sendreferer}, prefix => q{true} },
				49 => { name => q{size}, prefix => q{} },
				50 => { name => q{src}, prefix => q{} },
				51 => { name => q{ordered}, prefix => q{true} },
				52 => { name => q{ordered}, prefix => q{false} },
				53 => { name => q{tabindex}, prefix => q{} },
				54 => { name => q{title}, prefix => q{} },
				55 => { name => q{type}, prefix => q{} },
				56 => { name => q{type}, prefix => q{accept} },
				57 => { name => q{type}, prefix => q{delete} },
				58 => { name => q{type}, prefix => q{help} },
				59 => { name => q{type}, prefix => q{password} },
				60 => { name => q{type}, prefix => q{onpick} },
				61 => { name => q{type}, prefix => q{onenterbackward} },
				62 => { name => q{type}, prefix => q{onenterforward} },
				63 => { name => q{type}, prefix => q{ontimer} },
				69 => { name => q{type}, prefix => q{options} },
				70 => { name => q{type}, prefix => q{prev} },
				71 => { name => q{type}, prefix => q{reset} },
				72 => { name => q{type}, prefix => q{text} },
				73 => { name => q{type}, prefix => q{vnd.} },
				74 => { name => q{href}, prefix => q{} },
				75 => { name => q{href}, prefix => q{http://} },
				76 => { name => q{href}, prefix => q{https://} },
				77 => { name => q{value}, prefix => q{} },
				78 => { name => q{vspace}, prefix => q{} },
				79 => { name => q{width}, prefix => q{} },
				80 => { name => q{xml:lang}, prefix => q{} },
				82 => { name => q{align}, prefix => q{} },
				83 => { name => q{columns}, prefix => q{} },
				84 => { name => q{class}, prefix => q{} },
				85 => { name => q{id}, prefix => q{} },
				86 => { name => q{forua}, prefix => q{false} },
				87 => { name => q{forua}, prefix => q{true} },
				88 => { name => q{src}, prefix => q{http://} },
				89 => { name => q{src}, prefix => q{https://} },
				90 => { name => q{http-equiv}, prefix => q{} },
				91 => { name => q{http-equiv}, prefix => q{Content-Type} },
				92 => { name => q{content}, prefix => q{application/vnd.wap.wmlc;charset=} },
				93 => { name => q{http-equiv}, prefix => q{Expires} },
				94 => { name => q{accesskey}, prefix => q{} },
				95 => { name => q{enctype}, prefix => q{} },
				96 => { name => q{enctype}, prefix => q{application/x-www-form-urlencoded} },
				97 => { name => q{enctype}, prefix => q{multipart/form-data} },
				98 => { name => q{xml:space}, prefix => q{preserve} },
				99 => { name => q{xml:space}, prefix => q{default} },
				100 => { name => q{cache-control}, prefix => q{no-cache} },
			},
		},
		attrvalue => {
			0 => {
				133 => q{.com/},
				134 => q{.edu/},
				135 => q{.net/},
				136 => q{.org/},
				137 => q{accept},
				138 => q{bottom},
				139 => q{clear},
				140 => q{delete},
				141 => q{help},
				142 => q{http://},
				143 => q{http://www.},
				144 => q{https://},
				145 => q{https://www.},
				147 => q{middle},
				148 => q{nowrap},
				149 => q{onpick},
				150 => q{onenterbackward},
				151 => q{onenterforward},
				152 => q{ontimer},
				153 => q{options},
				154 => q{password},
				155 => q{reset},
				157 => q{text},
				158 => q{top},
				159 => q{unknown},
				160 => q{wrap},
				161 => q{www.},
			},
		},
	},
	"-//WAPFORUM//DTD WML 1.2//EN" => {
		tag => {
			0 => {
				27 => q{pre},
				28 => q{a},
				29 => q{td},
				30 => q{tr},
				31 => q{table},
				32 => q{p},
				33 => q{postfield},
				34 => q{anchor},
				35 => q{access},
				36 => q{b},
				37 => q{big},
				38 => q{br},
				39 => q{card},
				40 => q{do},
				41 => q{em},
				42 => q{fieldset},
				43 => q{go},
				44 => q{head},
				45 => q{i},
				46 => q{img},
				47 => q{input},
				48 => q{meta},
				49 => q{noop},
				50 => q{prev},
				51 => q{onevent},
				52 => q{optgroup},
				53 => q{option},
				54 => q{refresh},
				55 => q{select},
				56 => q{small},
				57 => q{strong},
				59 => q{template},
				60 => q{timer},
				61 => q{u},
				62 => q{setvar},
				63 => q{wml},
			},
		},
		attrstart => {
			0 => {
				0 => { name => q{xml:space}, prefix => q{preserve} },
				5 => { name => q{accept-charset}, prefix => q{} },
				6 => { name => q{align}, prefix => q{bottom} },
				7 => { name => q{align}, prefix => q{center} },
				8 => { name => q{align}, prefix => q{left} },
				9 => { name => q{align}, prefix => q{middle} },
				10 => { name => q{align}, prefix => q{right} },
				11 => { name => q{align}, prefix => q{top} },
				12 => { name => q{alt}, prefix => q{} },
				13 => { name => q{content}, prefix => q{} },
				15 => { name => q{domain}, prefix => q{} },
				16 => { name => q{emptyok}, prefix => q{false} },
				17 => { name => q{emptyok}, prefix => q{true} },
				18 => { name => q{format}, prefix => q{} },
				19 => { name => q{height}, prefix => q{} },
				20 => { name => q{hspace}, prefix => q{} },
				21 => { name => q{ivalue}, prefix => q{} },
				22 => { name => q{iname}, prefix => q{} },
				24 => { name => q{label}, prefix => q{} },
				25 => { name => q{localsrc}, prefix => q{} },
				26 => { name => q{maxlength}, prefix => q{} },
				27 => { name => q{method}, prefix => q{get} },
				28 => { name => q{method}, prefix => q{post} },
				29 => { name => q{mode}, prefix => q{nowrap} },
				30 => { name => q{mode}, prefix => q{wrap} },
				31 => { name => q{multiple}, prefix => q{false} },
				32 => { name => q{multiple}, prefix => q{true} },
				33 => { name => q{name}, prefix => q{} },
				34 => { name => q{newcontext}, prefix => q{false} },
				35 => { name => q{newcontext}, prefix => q{true} },
				36 => { name => q{onpick}, prefix => q{} },
				37 => { name => q{onenterbackward}, prefix => q{} },
				38 => { name => q{onenterforward}, prefix => q{} },
				39 => { name => q{ontimer}, prefix => q{} },
				40 => { name => q{optional}, prefix => q{false} },
				41 => { name => q{optional}, prefix => q{true} },
				42 => { name => q{path}, prefix => q{} },
				46 => { name => q{scheme}, prefix => q{} },
				47 => { name => q{sendreferer}, prefix => q{false} },
				48 => { name => q{sendreferer}, prefix => q{true} },
				49 => { name => q{size}, prefix => q{} },
				50 => { name => q{src}, prefix => q{} },
				51 => { name => q{ordered}, prefix => q{true} },
				52 => { name => q{ordered}, prefix => q{false} },
				53 => { name => q{tabindex}, prefix => q{} },
				54 => { name => q{title}, prefix => q{} },
				55 => { name => q{type}, prefix => q{} },
				56 => { name => q{type}, prefix => q{accept} },
				57 => { name => q{type}, prefix => q{delete} },
				58 => { name => q{type}, prefix => q{help} },
				59 => { name => q{type}, prefix => q{password} },
				60 => { name => q{type}, prefix => q{onpick} },
				61 => { name => q{type}, prefix => q{onenterbackward} },
				62 => { name => q{type}, prefix => q{onenterforward} },
				63 => { name => q{type}, prefix => q{ontimer} },
				69 => { name => q{type}, prefix => q{options} },
				70 => { name => q{type}, prefix => q{prev} },
				71 => { name => q{type}, prefix => q{reset} },
				72 => { name => q{type}, prefix => q{text} },
				73 => { name => q{type}, prefix => q{vnd.} },
				74 => { name => q{href}, prefix => q{} },
				75 => { name => q{href}, prefix => q{http://} },
				76 => { name => q{href}, prefix => q{https://} },
				77 => { name => q{value}, prefix => q{} },
				78 => { name => q{vspace}, prefix => q{} },
				79 => { name => q{width}, prefix => q{} },
				80 => { name => q{xml:lang}, prefix => q{} },
				82 => { name => q{align}, prefix => q{} },
				83 => { name => q{columns}, prefix => q{} },
				84 => { name => q{class}, prefix => q{} },
				85 => { name => q{id}, prefix => q{} },
				86 => { name => q{forua}, prefix => q{false} },
				87 => { name => q{forua}, prefix => q{true} },
				88 => { name => q{src}, prefix => q{http://} },
				89 => { name => q{src}, prefix => q{https://} },
				90 => { name => q{http-equiv}, prefix => q{} },
				91 => { name => q{http-equiv}, prefix => q{Content-Type} },
				92 => { name => q{content}, prefix => q{application/vnd.wap.wmlc;charset=} },
				93 => { name => q{http-equiv}, prefix => q{Expires} },
				94 => { name => q{accesskey}, prefix => q{} },
				95 => { name => q{enctype}, prefix => q{} },
				96 => { name => q{enctype}, prefix => q{application/x-www-form-urlencoded} },
				97 => { name => q{enctype}, prefix => q{multipart/form-data} },
			},
		},
		attrvalue => {
			0 => {
				133 => q{.com/},
				134 => q{.edu/},
				135 => q{.net/},
				136 => q{.org/},
				137 => q{accept},
				138 => q{bottom},
				139 => q{clear},
				140 => q{delete},
				141 => q{help},
				142 => q{http://},
				143 => q{http://www.},
				144 => q{https://},
				145 => q{https://www.},
				147 => q{middle},
				148 => q{nowrap},
				149 => q{onpick},
				150 => q{onenterbackward},
				151 => q{onenterforward},
				152 => q{ontimer},
				153 => q{options},
				154 => q{password},
				155 => q{reset},
				157 => q{text},
				158 => q{top},
				159 => q{unknown},
				160 => q{wrap},
				161 => q{www.},
			},
		},
	},
	"-//WAPFORUM//DTD WML 1.1//EN" => {
		tag => {
			0 => {
				28 => q{a},
				29 => q{td},
				30 => q{tr},
				31 => q{table},
				32 => q{p},
				33 => q{postfield},
				34 => q{anchor},
				35 => q{access},
				36 => q{b},
				37 => q{big},
				38 => q{br},
				39 => q{card},
				40 => q{do},
				41 => q{em},
				42 => q{fieldset},
				43 => q{go},
				44 => q{head},
				45 => q{i},
				46 => q{img},
				47 => q{input},
				48 => q{meta},
				49 => q{noop},
				50 => q{prev},
				51 => q{onevent},
				52 => q{optgroup},
				53 => q{option},
				54 => q{refresh},
				55 => q{select},
				56 => q{small},
				57 => q{strong},
				59 => q{template},
				60 => q{timer},
				61 => q{u},
				62 => q{setvar},
				63 => q{wml},
			},
		},
		attrstart => {
			0 => {
				5 => { name => q{accept-charset}, prefix => q{} },
				6 => { name => q{align}, prefix => q{bottom} },
				7 => { name => q{align}, prefix => q{center} },
				8 => { name => q{align}, prefix => q{left} },
				9 => { name => q{align}, prefix => q{middle} },
				10 => { name => q{align}, prefix => q{right} },
				11 => { name => q{align}, prefix => q{top} },
				12 => { name => q{alt}, prefix => q{} },
				13 => { name => q{content}, prefix => q{} },
				15 => { name => q{domain}, prefix => q{} },
				16 => { name => q{emptyok}, prefix => q{false} },
				17 => { name => q{emptyok}, prefix => q{true} },
				18 => { name => q{format}, prefix => q{} },
				19 => { name => q{height}, prefix => q{} },
				20 => { name => q{hspace}, prefix => q{} },
				21 => { name => q{ivalue}, prefix => q{} },
				22 => { name => q{iname}, prefix => q{} },
				24 => { name => q{label}, prefix => q{} },
				25 => { name => q{localsrc}, prefix => q{} },
				26 => { name => q{maxlength}, prefix => q{} },
				27 => { name => q{method}, prefix => q{get} },
				28 => { name => q{method}, prefix => q{post} },
				29 => { name => q{mode}, prefix => q{nowrap} },
				30 => { name => q{mode}, prefix => q{wrap} },
				31 => { name => q{multiple}, prefix => q{false} },
				32 => { name => q{multiple}, prefix => q{true} },
				33 => { name => q{name}, prefix => q{} },
				34 => { name => q{newcontext}, prefix => q{false} },
				35 => { name => q{newcontext}, prefix => q{true} },
				36 => { name => q{onpick}, prefix => q{} },
				37 => { name => q{onenterbackward}, prefix => q{} },
				38 => { name => q{onenterforward}, prefix => q{} },
				39 => { name => q{ontimer}, prefix => q{} },
				40 => { name => q{optional}, prefix => q{false} },
				41 => { name => q{optional}, prefix => q{true} },
				42 => { name => q{path}, prefix => q{} },
				46 => { name => q{scheme}, prefix => q{} },
				47 => { name => q{sendreferer}, prefix => q{false} },
				48 => { name => q{sendreferer}, prefix => q{true} },
				49 => { name => q{size}, prefix => q{} },
				50 => { name => q{src}, prefix => q{} },
				51 => { name => q{ordered}, prefix => q{true} },
				52 => { name => q{ordered}, prefix => q{false} },
				53 => { name => q{tabindex}, prefix => q{} },
				54 => { name => q{title}, prefix => q{} },
				55 => { name => q{type}, prefix => q{} },
				56 => { name => q{type}, prefix => q{accept} },
				57 => { name => q{type}, prefix => q{delete} },
				58 => { name => q{type}, prefix => q{help} },
				59 => { name => q{type}, prefix => q{password} },
				60 => { name => q{type}, prefix => q{onpick} },
				61 => { name => q{type}, prefix => q{onenterbackward} },
				62 => { name => q{type}, prefix => q{onenterforward} },
				63 => { name => q{type}, prefix => q{ontimer} },
				69 => { name => q{type}, prefix => q{options} },
				70 => { name => q{type}, prefix => q{prev} },
				71 => { name => q{type}, prefix => q{reset} },
				72 => { name => q{type}, prefix => q{text} },
				73 => { name => q{type}, prefix => q{vnd.} },
				74 => { name => q{href}, prefix => q{} },
				75 => { name => q{href}, prefix => q{http://} },
				76 => { name => q{href}, prefix => q{https://} },
				77 => { name => q{value}, prefix => q{} },
				78 => { name => q{vspace}, prefix => q{} },
				79 => { name => q{width}, prefix => q{} },
				80 => { name => q{xml:lang}, prefix => q{} },
				82 => { name => q{align}, prefix => q{} },
				83 => { name => q{columns}, prefix => q{} },
				84 => { name => q{class}, prefix => q{} },
				85 => { name => q{id}, prefix => q{} },
				86 => { name => q{forua}, prefix => q{false} },
				87 => { name => q{forua}, prefix => q{true} },
				88 => { name => q{src}, prefix => q{http://} },
				89 => { name => q{src}, prefix => q{https://} },
				90 => { name => q{http-equiv}, prefix => q{} },
				91 => { name => q{http-equiv}, prefix => q{Content-Type} },
				92 => { name => q{content}, prefix => q{application/vnd.wap.wmlc;charset=} },
				93 => { name => q{http-equiv}, prefix => q{Expires} },
			},
		},
		attrvalue => {
			0 => {
				133 => q{.com/},
				134 => q{.edu/},
				135 => q{.net/},
				136 => q{.org/},
				137 => q{accept},
				138 => q{bottom},
				139 => q{clear},
				140 => q{delete},
				141 => q{help},
				142 => q{http://},
				143 => q{http://www.},
				144 => q{https://},
				145 => q{https://www.},
				147 => q{middle},
				148 => q{nowrap},
				149 => q{onpick},
				150 => q{onenterbackward},
				151 => q{onenterforward},
				152 => q{ontimer},
				153 => q{options},
				154 => q{password},
				155 => q{reset},
				157 => q{text},
				158 => q{top},
				159 => q{unknown},
				160 => q{wrap},
				161 => q{www.},
			},
		},
	},
	"-//WAPFORUM//DTD WML 1.0//EN" => {
		tag => {
			0 => {
				34 => q{A},
				35 => q{ACCESS},
				36 => q{B},
				37 => q{BIG},
				38 => q{BR},
				39 => q{CARD},
				40 => q{DO},
				41 => q{EM},
				42 => q{FIELSET},
				43 => q{GO},
				44 => q{HEAD},
				45 => q{I},
				46 => q{IMG},
				47 => q{INPUT},
				48 => q{META},
				49 => q{NOOP},
				50 => q{PREV},
				51 => q{ONEVENT},
				52 => q{OPTGROUP},
				53 => q{OPTION},
				54 => q{REFRESH},
				55 => q{SELECT},
				56 => q{SMALL},
				57 => q{STRONG},
				58 => q{TAB},
				59 => q{TEMPLATE},
				60 => q{TIMER},
				61 => q{U},
				62 => q{VAR},
				63 => q{WML},
			},
		},
		attrstart => {
			0 => {
				5 => { name => q{ACCEPT-CHARSET}, prefix => q{} },
				6 => { name => q{ALIGN}, prefix => q{BOTTOM} },
				7 => { name => q{ALIGN}, prefix => q{CENTER} },
				8 => { name => q{ALIGN}, prefix => q{LEFT} },
				9 => { name => q{ALIGN}, prefix => q{MIDDLE} },
				10 => { name => q{ALIGN}, prefix => q{RIGHT} },
				11 => { name => q{ALIGN}, prefix => q{TOP} },
				12 => { name => q{ALT}, prefix => q{} },
				13 => { name => q{CONTENT}, prefix => q{} },
				14 => { name => q{DEFAULT}, prefix => q{} },
				15 => { name => q{DOMAIN}, prefix => q{} },
				16 => { name => q{EMPTYOK}, prefix => q{FALSE} },
				17 => { name => q{EMPTYOK}, prefix => q{TRUE} },
				18 => { name => q{FORMAT}, prefix => q{} },
				19 => { name => q{HEIGHT}, prefix => q{} },
				20 => { name => q{HSPACE}, prefix => q{} },
				21 => { name => q{IDEFAULT}, prefix => q{} },
				22 => { name => q{IKEY}, prefix => q{} },
				23 => { name => q{KEY}, prefix => q{} },
				24 => { name => q{LABEL}, prefix => q{} },
				25 => { name => q{LOCALSRC}, prefix => q{} },
				26 => { name => q{MAXLENGTH}, prefix => q{} },
				27 => { name => q{METHOD}, prefix => q{GET} },
				28 => { name => q{METHOD}, prefix => q{POST} },
				29 => { name => q{MODE}, prefix => q{NOWRAP} },
				30 => { name => q{MODE}, prefix => q{WRAP} },
				31 => { name => q{MULTIPLE}, prefix => q{FALSE} },
				32 => { name => q{MULTIPLE}, prefix => q{TRUE} },
				33 => { name => q{NAME}, prefix => q{} },
				34 => { name => q{NEWCONTEXT}, prefix => q{FALSE} },
				35 => { name => q{NEWCONTEXT}, prefix => q{TRUE} },
				36 => { name => q{ONCLICK}, prefix => q{} },
				37 => { name => q{ONENTERBACKWARD}, prefix => q{} },
				38 => { name => q{ONENTERFORWARD}, prefix => q{} },
				39 => { name => q{ONTIMER}, prefix => q{} },
				40 => { name => q{OPTIONAL}, prefix => q{FALSE} },
				41 => { name => q{OPTIONAL}, prefix => q{TRUE} },
				42 => { name => q{PATH}, prefix => q{} },
				43 => { name => q{POSTDATA}, prefix => q{} },
				44 => { name => q{PUBLIC}, prefix => q{FALSE} },
				45 => { name => q{PUBLIC}, prefix => q{TRUE} },
				46 => { name => q{SCHEME}, prefix => q{} },
				47 => { name => q{SENDREFERER}, prefix => q{FALSE} },
				48 => { name => q{SENDREFERER}, prefix => q{TRUE} },
				49 => { name => q{SIZE}, prefix => q{} },
				50 => { name => q{SRC}, prefix => q{} },
				51 => { name => q{STYLE}, prefix => q{LIST} },
				52 => { name => q{STYLE}, prefix => q{SET} },
				53 => { name => q{TABINDEX}, prefix => q{} },
				54 => { name => q{TITLE}, prefix => q{} },
				55 => { name => q{TYPE}, prefix => q{} },
				56 => { name => q{TYPE}, prefix => q{ACCEPT} },
				57 => { name => q{TYPE}, prefix => q{DELETE} },
				58 => { name => q{TYPE}, prefix => q{HELP} },
				59 => { name => q{TYPE}, prefix => q{PASSWORD} },
				60 => { name => q{TYPE}, prefix => q{ONCLICK} },
				61 => { name => q{TYPE}, prefix => q{ONENTERBACKWARD} },
				62 => { name => q{TYPE}, prefix => q{ONENTERFORWARD} },
				63 => { name => q{TYPE}, prefix => q{ONTIMER} },
				69 => { name => q{TYPE}, prefix => q{OPTIONS} },
				70 => { name => q{TYPE}, prefix => q{PREV} },
				71 => { name => q{TYPE}, prefix => q{RESET} },
				72 => { name => q{TYPE}, prefix => q{TEXT} },
				73 => { name => q{TYPE}, prefix => q{vnd.} },
				74 => { name => q{URL}, prefix => q{} },
				75 => { name => q{URL}, prefix => q{http://} },
				76 => { name => q{URL}, prefix => q{https://} },
				77 => { name => q{USER-AGENT}, prefix => q{} },
				78 => { name => q{VALUE}, prefix => q{} },
				79 => { name => q{VSPACE}, prefix => q{} },
				80 => { name => q{WIDTH}, prefix => q{} },
				81 => { name => q{xml:lang}, prefix => q{} },
			},
		},
		attrvalue => {
			0 => {
				133 => q{.com/},
				134 => q{.edu/},
				135 => q{.net/},
				136 => q{.org/},
				137 => q{ACCEPT},
				138 => q{BOTTOM},
				139 => q{CLEAR},
				140 => q{DELETE},
				141 => q{HELP},
				142 => q{http://},
				143 => q{http://www.},
				144 => q{https://},
				145 => q{https://www.},
				146 => q{LIST},
				147 => q{MIDDLE},
				148 => q{NOWRAP},
				149 => q{ONCLICK},
				150 => q{ONENTERBACKWARD},
				151 => q{ONENTERFORWARD},
				152 => q{ONTIMER},
				153 => q{OPTIONS},
				154 => q{PASSWORD},
				155 => q{RESET},
				156 => q{SET},
				157 => q{TEXT},
				158 => q{TOP},
				159 => q{UNKNOWN},
				160 => q{WRAP},
				161 => q{www.},
			},
		},
	},
	"-//WAPFORUM//DTD PROV 1.0//EN" => {
		tag => {
			0 => {
				5 => q{wap-provisioningdoc},
				6 => q{characteristic},
				7 => q{parm},
			},
		},
		attrstart => {
			0 => {
				5 => { name => q{name}, prefix => q{} },
				6 => { name => q{value}, prefix => q{} },
				7 => { name => q{name}, prefix => q{NAME} },
				8 => { name => q{name}, prefix => q{NAP-ADDRESS} },
				9 => { name => q{name}, prefix => q{NAP-ADDRTYPE} },
				10 => { name => q{name}, prefix => q{CALLTYPE} },
				11 => { name => q{name}, prefix => q{VALIDUNTIL} },
				12 => { name => q{name}, prefix => q{AUTHTYPE} },
				13 => { name => q{name}, prefix => q{AUTHNAME} },
				14 => { name => q{name}, prefix => q{AUTHSECRET} },
				15 => { name => q{name}, prefix => q{LINGER} },
				16 => { name => q{name}, prefix => q{BEARER} },
				17 => { name => q{name}, prefix => q{NAPID} },
				18 => { name => q{name}, prefix => q{COUNTRY} },
				19 => { name => q{name}, prefix => q{NETWORK} },
				20 => { name => q{name}, prefix => q{INTERNET} },
				21 => { name => q{name}, prefix => q{PROXY-ID} },
				22 => { name => q{name}, prefix => q{PROXY-PROVIDER-ID} },
				23 => { name => q{name}, prefix => q{DOMAIN} },
				24 => { name => q{name}, prefix => q{PROVURL} },
				25 => { name => q{name}, prefix => q{PXAUTH-TYPE} },
				26 => { name => q{name}, prefix => q{PXAUTH-ID} },
				27 => { name => q{name}, prefix => q{PXAUTH-PW} },
				28 => { name => q{name}, prefix => q{STARTPAGE} },
				29 => { name => q{name}, prefix => q{BASAUTH-ID} },
				30 => { name => q{name}, prefix => q{BASAUTH-PW} },
				31 => { name => q{name}, prefix => q{PUSHENABLED} },
				32 => { name => q{name}, prefix => q{PXADDR} },
				33 => { name => q{name}, prefix => q{PXADDRTYPE} },
				34 => { name => q{name}, prefix => q{TO-NAPID} },
				35 => { name => q{name}, prefix => q{PORTNBR} },
				36 => { name => q{name}, prefix => q{SERVICE} },
				37 => { name => q{name}, prefix => q{LINKSPEED} },
				38 => { name => q{name}, prefix => q{DNLINKSPEED} },
				39 => { name => q{name}, prefix => q{LOCAL-ADDR} },
				40 => { name => q{name}, prefix => q{LOCAL-ADDRTYPE} },
				41 => { name => q{name}, prefix => q{CONTEXT-ALLOW} },
				42 => { name => q{name}, prefix => q{TRUST} },
				43 => { name => q{name}, prefix => q{MASTER} },
				44 => { name => q{name}, prefix => q{SID} },
				45 => { name => q{name}, prefix => q{SOC} },
				46 => { name => q{name}, prefix => q{WSP-VERSION} },
				47 => { name => q{name}, prefix => q{PHYSICAL-PROXY-ID} },
				48 => { name => q{name}, prefix => q{CLIENT-ID} },
				49 => { name => q{name}, prefix => q{DELIVERY-ERR-SDU} },
				50 => { name => q{name}, prefix => q{DELIVERY-ORDER} },
				51 => { name => q{name}, prefix => q{TRAFFIC-CLASS} },
				52 => { name => q{name}, prefix => q{MAX-SDU-SIZE} },
				53 => { name => q{name}, prefix => q{MAX-BITRATE-UPLINK} },
				54 => { name => q{name}, prefix => q{MAX-BITRATE-DNLINK} },
				55 => { name => q{name}, prefix => q{RESIDUAL-BER} },
				56 => { name => q{name}, prefix => q{SDU-ERROR-RATIO} },
				57 => { name => q{name}, prefix => q{TRAFFIC-HANDL-PRIO} },
				58 => { name => q{name}, prefix => q{TRANSFER-DELAY} },
				59 => { name => q{name}, prefix => q{GUARANTEED-BITRATE-UPLINK} },
				60 => { name => q{name}, prefix => q{GUARANTEED-BITRATE-DNLINK} },
				69 => { name => q{version}, prefix => q{} },
				70 => { name => q{version}, prefix => q{1.0} },
				80 => { name => q{type}, prefix => q{} },
				81 => { name => q{type}, prefix => q{PXLOGICAL} },
				82 => { name => q{type}, prefix => q{PXPHYSICAL} },
				83 => { name => q{type}, prefix => q{PORT} },
				84 => { name => q{type}, prefix => q{VALIDITY} },
				85 => { name => q{type}, prefix => q{NAPDEF} },
				86 => { name => q{type}, prefix => q{BOOTSTRAP} },
				87 => { name => q{type}, prefix => q{VENDORCONFIG} },
				88 => { name => q{type}, prefix => q{CLIENTIDENTITY} },
				89 => { name => q{type}, prefix => q{PXAUTHINFO} },
				90 => { name => q{type}, prefix => q{NAPAUTHINFO} },
			},
		},
		attrvalue => {
			0 => {
				133 => q{IPV4},
				134 => q{IPV6},
				135 => q{E164},
				136 => q{ALPHA},
				137 => q{APN},
				138 => q{SCODE},
				139 => q{TETRA-ITSI},
				140 => q{MAN},
				144 => q{ANALOG-MODEM},
				145 => q{V.120},
				146 => q{V.110},
				147 => q{X.31},
				148 => q{BIT-TRANSPARENT},
				149 => q{DIRECT-ASYNCHRONOUS-DATA-SERVICE},
				154 => q{PAP},
				155 => q{CHAP},
				156 => q{HTTP-BASIC},
				157 => q{HTTP-DIGEST},
				158 => q{WTLS-SS},
				162 => q{GSM-USSD},
				163 => q{GSM-SMS},
				164 => q{ANSI-136-GUTS},
				165 => q{IS-95-CDMA-SMS},
				166 => q{IS-95-CDMA-CSD},
				167 => q{IS-95-CDMA-PACKET},
				168 => q{ANSI-136-CSD},
				169 => q{ANSI-136-GPRS},
				170 => q{GSM-CSD},
				171 => q{GSM-GPRS},
				172 => q{AMPS-CDPD},
				173 => q{PDC-CSD},
				174 => q{PDC-PACKET},
				175 => q{IDEN-SMS},
				176 => q{IDEN-CSD},
				177 => q{IDEN-PACKET},
				178 => q{FLEX/REFLEX},
				179 => q{PHS-SMS},
				180 => q{PHS-CSD},
				181 => q{TETRA-SDS},
				182 => q{TETRA-PACKET},
				183 => q{ANSI-136-GHOST},
				184 => q{MOBITEX-MPAK},
				197 => q{AUTOBAUDING},
				202 => q{CL-WSP},
				203 => q{CO-WSP},
				204 => q{CL-SEC-WSP},
				205 => q{CO-SEC-WSP},
				206 => q{CL-SEC-WTA},
				207 => q{CO-SEC-WTA},
			},
		},
	},
	"-//WAPFORUM//DTD WTA-WML 1.2//EN" => {
		tag => {
			0 => {
				27 => q{pre},
				28 => q{a},
				29 => q{td},
				30 => q{tr},
				31 => q{table},
				32 => q{p},
				33 => q{postfield},
				34 => q{anchor},
				35 => q{access},
				36 => q{b},
				37 => q{big},
				38 => q{br},
				39 => q{card},
				40 => q{do},
				41 => q{em},
				42 => q{fieldset},
				43 => q{go},
				44 => q{head},
				45 => q{i},
				46 => q{img},
				47 => q{input},
				48 => q{meta},
				49 => q{noop},
				50 => q{prev},
				51 => q{onevent},
				52 => q{optgroup},
				53 => q{option},
				54 => q{refresh},
				55 => q{select},
				56 => q{small},
				57 => q{strong},
				59 => q{template},
				60 => q{timer},
				61 => q{u},
				62 => q{setvar},
			},
			1 => {
				63 => q{wta-wml},
			},
		},
		attrstart => {
			0 => {
				0 => { name => q{xml:space}, prefix => q{preserve} },
				10 => { name => q{align}, prefix => q{right} },
				11 => { name => q{align}, prefix => q{top} },
				12 => { name => q{alt}, prefix => q{} },
				13 => { name => q{content}, prefix => q{} },
				15 => { name => q{domain}, prefix => q{} },
				24 => { name => q{label}, prefix => q{} },
				25 => { name => q{localsrc}, prefix => q{} },
				26 => { name => q{maxlength}, prefix => q{} },
				27 => { name => q{method}, prefix => q{get} },
				28 => { name => q{method}, prefix => q{post} },
				29 => { name => q{mode}, prefix => q{nowrap} },
				30 => { name => q{mode}, prefix => q{wrap} },
				31 => { name => q{multiple}, prefix => q{false} },
				35 => { name => q{newcontext}, prefix => q{true} },
				36 => { name => q{onpick}, prefix => q{} },
				37 => { name => q{onenterbackward}, prefix => q{} },
				38 => { name => q{onenterforward}, prefix => q{} },
				39 => { name => q{ontimer}, prefix => q{} },
				40 => { name => q{optional}, prefix => q{false} },
				41 => { name => q{optional}, prefix => q{true} },
				42 => { name => q{path}, prefix => q{} },
				46 => { name => q{scheme}, prefix => q{} },
				47 => { name => q{sendreferer}, prefix => q{false} },
				49 => { name => q{size}, prefix => q{} },
				50 => { name => q{src}, prefix => q{} },
				51 => { name => q{ordered}, prefix => q{true} },
				52 => { name => q{ordered}, prefix => q{false} },
				53 => { name => q{tabindex}, prefix => q{} },
				54 => { name => q{title}, prefix => q{} },
				55 => { name => q{type}, prefix => q{} },
				57 => { name => q{type}, prefix => q{delete} },
				58 => { name => q{type}, prefix => q{help} },
				59 => { name => q{type}, prefix => q{password} },
				60 => { name => q{type}, prefix => q{onpick} },
				61 => { name => q{type}, prefix => q{onenterbackward} },
				62 => { name => q{type}, prefix => q{onenterforward} },
				63 => { name => q{type}, prefix => q{ontimer} },
				69 => { name => q{type}, prefix => q{options} },
				70 => { name => q{type}, prefix => q{prev} },
				71 => { name => q{type}, prefix => q{reset} },
				72 => { name => q{type}, prefix => q{text} },
				73 => { name => q{type}, prefix => q{vnd.} },
				74 => { name => q{href}, prefix => q{} },
				75 => { name => q{href}, prefix => q{http://} },
				76 => { name => q{href}, prefix => q{https://} },
				77 => { name => q{value}, prefix => q{} },
				78 => { name => q{vspace}, prefix => q{} },
				79 => { name => q{width}, prefix => q{} },
				82 => { name => q{align}, prefix => q{} },
				83 => { name => q{columns}, prefix => q{} },
				84 => { name => q{class}, prefix => q{} },
				85 => { name => q{id}, prefix => q{} },
				86 => { name => q{forua}, prefix => q{false} },
				87 => { name => q{forua}, prefix => q{true} },
				92 => { name => q{content}, prefix => q{application/vnd.wap.wmlc;charset=} },
				93 => { name => q{http-equiv}, prefix => q{Expires} },
				94 => { name => q{accesskey}, prefix => q{} },
				95 => { name => q{enctype}, prefix => q{} },
				97 => { name => q{enctype}, prefix => q{multipart/form-data} },
			},
			1 => {
				5 => { name => q{href}, prefix => q{wtai://} },
				6 => { name => q{href}, prefix => q{wtai://wp/mc;} },
				7 => { name => q{href}, prefix => q{wtai://wp/sd;} },
				8 => { name => q{href}, prefix => q{wtai://wp/ap;} },
				9 => { name => q{href}, prefix => q{wtai://ms/ec} },
				16 => { name => q{type}, prefix => q{wtaev-} },
				17 => { name => q{type}, prefix => q{wtaev-cc/} },
				18 => { name => q{type}, prefix => q{wtaev-cc/ic} },
				19 => { name => q{type}, prefix => q{wtaev-cc/cl} },
				20 => { name => q{type}, prefix => q{wtaev-cc/co} },
				21 => { name => q{type}, prefix => q{wtaev-cc/oc} },
				22 => { name => q{type}, prefix => q{wtaev-cc/cc} },
				23 => { name => q{type}, prefix => q{wtaev-cc/dtmf} },
				32 => { name => q{type}, prefix => q{wtaev-nt/} },
				33 => { name => q{type}, prefix => q{wtaev-nt/it} },
				34 => { name => q{type}, prefix => q{wtaev-nt/st} },
				48 => { name => q{type}, prefix => q{wtaev-pb/} },
				56 => { name => q{type}, prefix => q{wtaev-lg/} },
				80 => { name => q{type}, prefix => q{wtaev-ms/} },
				81 => { name => q{type}, prefix => q{wtaev-ms/ns} },
				88 => { name => q{type}, prefix => q{wtaev-gsm/} },
				89 => { name => q{type}, prefix => q{wtaev-gsm/ru} },
				90 => { name => q{type}, prefix => q{wtaev-gsm/ch} },
				91 => { name => q{type}, prefix => q{wtaev-gsm/ca} },
				96 => { name => q{type}, prefix => q{wtaev-pdc/} },
				104 => { name => q{type}, prefix => q{wtaev-ansi136/} },
				105 => { name => q{type}, prefix => q{wtaev-ansi136/ia} },
				106 => { name => q{type}, prefix => q{wtaev-ansi136/if} },
				112 => { name => q{type}, prefix => q{wtaev-cdma/} },
			},
		},
		attrvalue => {
			0 => {
				133 => q{.com/},
				134 => q{.edu/},
				135 => q{.net/},
				136 => q{.org/},
				137 => q{accept},
				138 => q{bottom},
				139 => q{clear},
				140 => q{delete},
				141 => q{help},
				142 => q{http://},
				143 => q{http://www.},
				144 => q{https://},
				145 => q{https://www.},
				147 => q{middle},
				148 => q{nowrap},
				149 => q{onpick},
				150 => q{onenterbackward},
				151 => q{onenterforward},
				152 => q{ontimer},
				153 => q{options},
				154 => q{password},
				155 => q{reset},
				157 => q{text},
				158 => q{top},
				159 => q{unknown},
				160 => q{wrap},
				161 => q{www.},
			},
		},
	},
	"-//W3C//DTD XHTML 1.0 Strict//EN" => {
		tag => {
		},
		attrstart => {
		},
		attrvalue => {
		},
	},
	"-//W3C//DTD XHTML 1.0 Transitional//EN" => {
		tag => {
		},
		attrstart => {
		},
		attrvalue => {
		},
	},
	"-//W3C//DTD XHTML 1.0 Frameset//EN" => {
		tag => {
		},
		attrstart => {
		},
		attrvalue => {
		},
	},
	"-//W3C//DTD XHTML 1.1//EN" => {
		tag => {
		},
		attrstart => {
		},
		attrvalue => {
		},
	},
	"-//W3C//DTD XHTML Basic 1.0//EN" => {
		tag => {
		},
		attrstart => {
		},
		attrvalue => {
		},
	},
);

=head1 ACCESSOR METHODS

=head2 charset

Returns the current charset, such as 'UTF-8'.

=cut

sub charset { $_[0]->{charset} }

=head2 publicid

Returns the current public ID, which is the XML DTD identifier for this
document, e.g. "-//WAPFORUM//DTD SI 1.0//EN".

=cut

sub publicid { $_[0]->{publicid} }

=head2 version

Returns current version as a string, e.g. "1.3".

=cut

sub version { shift->{version} }

=head2 codepage

Returns current codepage.

=cut

sub codepage { 0 }

=head1 METHODS

=head2 new

Constructor. Ignores everything you give it.

=cut

sub new {
	my $class = shift;
	my $self = bless { queue => [] }, $class;

# We apply these via handlers since we always want them to run first.
	$self->add_handler_for_event(
		version	=> sub {
			my ($self, $version) = @_;
			my $major = 1 + (($version & 0xF0) >> 4);
			my $minor = ($version & 0x0F);
			$self->{version} = "${major}.$minor";
			$self;
		},
		publicid => sub {
			my ($self, $publicid) = @_;
			my $type = $public_id{$publicid};
			$self->{ns} = $ns{$type};
			$self->{publicid} = $type;
			$self;
		},
		charset => sub {
			my ($self, $charset) = @_;
			$self->{charset} = mib_to_charset_name($charset);
			$self;
		},
	);
	$self;
}

=head2 mb_to_int

Convert multi-byte sequence to an integer value.

=cut

sub mb_to_int {
	my $self = shift;
	my $buffref = shift;
	return unless $$buffref =~ s/^([\x80-\xFF]*[\x00-\x7F])//;

	my $v = 0;
	$v = ($v << 7) + (ord($_) & 0x7F) for split //, $1;
	return $v;
}

=head2 decode_string

Decodes the given string using the current L</charset>.

=cut

sub decode_string {
	my $self = shift;
	return Encode::decode($self->charset, $_[0]);
}

=head2 encode_string

Encodes the given string using the current L</charset>.

=cut

sub encode_string {
	my $self = shift;
	return Encode::encode($self->charset, $_[0]);
}

=head2 parse

Parse as much as we can from the given buffer.

Takes a single scalar ref as parameter, this should point to the buffer
to be processed.

=cut

sub parse {
	my $self = shift;
	my $buffref = shift;
	$self->queue_start unless @{$self->{queue}};
	$self->process_queue($buffref);
}

=head2 queue_start

Queue the initial items for parsing.

=cut

sub queue_start {
	my $self = shift;
	$self->push_queued(qw(version publicid charset strtbl body));
	return $self;
}

=head2 process_queue

Process everything we can in the queue.

Takes a single scalar ref as parameter, this should point to the buffer
to be processed.

=cut

sub process_queue {
	my $self = shift;
	my $buffref = shift;

	ITEM:
	while(my $next = $self->next_queued) {
		last ITEM unless $self->parse_item($next, $buffref);
	}
}

=head2 next_queued

Return current item in the queue (without removing it).

=cut

sub next_queued {
	my $self = shift;
	$self->{queue}[0];
}

=head2 mark_item_complete

Remove the current item from the queue.

=cut

sub mark_item_complete {
	my $self = shift;
	shift @{$self->{queue}};
	$self;
}

=head2 push_queued

Queue some more items. More of a shift than a push.

=cut

sub push_queued {
	my $self = shift;
	unshift @{$self->{queue}}, @_;
	$self;
}

=head2 parse_item

Parse the given item if we have a method for it.

=cut

sub parse_item {
	my $self = shift;
	my $method = 'parse_' . shift;
	$self->$method(@_);
}

=head2 parse_version

Deconstruct a version - single byte containing major in the high nybble, minor in
the lower nybble.

=cut

sub parse_version {
	my ($self, $buffref) = @_;
	return unless length $$buffref;

	my ($version) = unpack 'C1', substr $$buffref, 0, 1, '';
	$self->mark_item_complete;
	$self->invoke_event(version => $version);
	return $self;
}

=head2 parse_publicid

Look up the given public ID, which is either a token for a preset value or
a reference to the string table.

=cut

sub parse_publicid {
	my ($self, $buffref) = @_;
	return unless length $$buffref;
	my $rslt = $self->mb_to_int($buffref);
	return unless defined $rslt;

	$self->mark_item_complete;
	$self->invoke_event(publicid => $rslt);
	return $self;
}

=head2 parse_charset

=cut

sub parse_charset {
	my ($self, $buffref) = @_;
	return unless length $$buffref;
	my $rslt = $self->mb_to_int($buffref);
	return unless defined $rslt;

	$self->mark_item_complete;
	$self->invoke_event(charset => $rslt);
	return $self;
}

=head2 parse_strtbl

=cut

sub parse_strtbl {
	my ($self, $buffref) = @_;
	$self->mark_item_complete;
	$self->push_queued(qw(strtbl_length));
	return $self;
}

=head2 parse_strtbl_length

=cut

sub parse_strtbl_length {
	my ($self, $buffref) = @_;
	return unless length $$buffref;
	my $rslt = $self->mb_to_int($buffref);
	return unless defined $rslt;

	$self->mark_item_complete;
	$self->invoke_event(strtbl_length => $rslt);
	$self->push_queued(qw(strtbl_data) x $rslt) if $rslt;
	return $self;
}

=head2 parse_strtbl_data

=cut

sub parse_strtbl_data {
	my ($self, $buffref) = @_;
	return unless length $$buffref;
	my ($byte) = unpack 'C1', substr $$buffref, 0, 1, '';
	$self->mark_item_complete;
	$self->invoke_event(strtbl => $byte);
	return $self;
}

=head2 parse_body

=cut

sub parse_body {
	my ($self, $buffref) = @_;
	$self->mark_item_complete;
	$self->push_queued(qw(pi element pi));
	return $self;
}

=head2 parse_pi

=cut

sub parse_pi {
	my ($self, $buffref) = @_;
	return unless length $$buffref;
	my $v = substr $$buffref, 0, 1;
	if(ord($v) == TOKEN_PI) {
		substr $$buffref, 0, 1, '';
	} else {
		$self->mark_item_complete;
	}
	$self;
}

=head2 parse_attribute

=cut

sub parse_attribute {
	my ($self, $buffref) = @_;
	return unless length $$buffref;

	my $v = substr $$buffref, 0, 1;
	if(ord($v) == TOKEN_END) {
		substr $$buffref, 0, 1, '';
		$self->mark_item_complete;
		$self->invoke_event(end_attributes => );
		return $self;
	}

	if(ord($v) == TOKEN_SWITCH_PAGE && length $$buffref > 2) {
		die "Switching page\n";
	}

	$self->mark_item_complete;

	if(defined(my $start = $self->attrstart_from_id(ord($v)))) {
		substr $$buffref, 0, 1, '';
		$self->{attribute_value} = $start->{prefix};
		$self->{attribute_name} = $start->{name};
		$self->push_queued(qw(attrvalue));
		return $self;
	} elsif(ord($v) == TOKEN_LITERAL) {
		die 'literal';
	}
	die "something else: " . $self->as_hex($$buffref);
	$self;
}

sub as_hex {
	my $self = shift;
	my $data = shift;
	warn " hex: " . join ' ', map sprintf('%02x', ord($_)), split //, $data;
	$self;
}

=head2 parse_attrvalue

=cut

sub parse_attrvalue {
	my $self = shift;
	my $buffref = shift;
	return unless length $$buffref;

	my $v = substr $$buffref, 0, 1;
	if(ord($v) == TOKEN_SWITCH_PAGE && length $$buffref > 2) {
		die "Switching page\n";
	}

	if(ord($v) == TOKEN_STR_I) {
		return unless substr($$buffref, 1) =~ /\0/;
		substr $$buffref, 0, 1, '';
		$$buffref =~ s/^(.*)\0//;
		my $str = $self->decode_string($1);
		$self->{attribute_value} .= $str;
		return $self;
	}
	if(ord($v) == TOKEN_STR_T) {
		die "Table ref!";
	}
	if(defined(my $start = $self->attrvalue_from_id(ord($v)))) {
		$self->{attribute_value} .= $start;
		substr $$buffref, 0, 1, '';
		return $self;
	}
	$self->invoke_event(attribute => $self->{attribute_name}, $self->{attribute_value});
	$self->mark_item_complete;
	$self->push_queued(qw(attribute));
	$self;
}

=head2 parse_element

=cut

sub parse_element {
	my ($self, $buffref) = @_;
	return unless length $$buffref;

	my $v = substr $$buffref, 0, 1;

# ([switchPage] stag)
	if(ord($v) == TOKEN_SWITCH_PAGE && length $$buffref > 2) {
		die "switch page";
		my $v = substr $$buffref, 0, 1;
	}

	if(grep ord($v) == $_, TOKEN_LITERAL, TOKEN_LITERAL_A, TOKEN_LITERAL_C, TOKEN_LITERAL_AC) {
		die "Have LITERAL\n";
	} else {
		my $tag_id = ord($v) & 0x3F;
		substr $$buffref, 0, 1, '';
		my $tag = $self->{ns}{tag}{$self->codepage}{$tag_id};
		$self->mark_item_complete;
		if(ord($v) & 0x80) {
			$self->{has_attributes} = 1;
			$self->push_queued(qw(attribute));
		} else {
			$self->{has_attributes} = 0;
			$self->invoke_event(start_element => {
				Name => $tag,
				LocalName => $tag,
				Attributes => { },
			});
		}
		if(ord($v) & 0x40) {
			$self->push_queued(qw(content));
		}
		$self->invoke_event(element => $tag);
	}

	$self;
}

=head2 tag_from_id

=cut

sub tag_from_id {
	my $self = shift;
	my $id = shift;
	$self->{ns}{tag}{$self->codepage}{$id}
}

=head2 attrstart_from_id

=cut

sub attrstart_from_id {
	my $self = shift;
	my $id = shift;
	$self->{ns}{attrstart}{$self->codepage}{$id}
}

=head2 attrvalue_from_id

=cut

sub attrvalue_from_id {
	my $self = shift;
	my $id = shift;
	$self->{ns}{attrvalue}{$self->codepage}{$id}
}

1;

__END__

=head1 NOTES

Probably more suited to L<Marpa::XS>-style parsing than a manual task stack/state machine,
so it's likely that the internals will be rearranged in the next version(s).

=head1 SEE ALSO

=over 4

=item * L<XML::WBXML> - wrapper around libwbxml2, faster and more robust than this module

=item * L<WAP::SAXDriver::wbxml> - provides SAX events from WBXML sources

=item * L<WAP::wbxml> - generic support for converting to/from WBXML

=item * L<CGI::WML> - also contains an XML-to-WBXML compiler

=item * Open Mobile Alliance documentation at L<http://www.openmobilealliance.org/tech/affiliates/syncml/syncmlindex.html>

=back

=head1 AUTHOR

Tom Molesworth <cpan@entitymodel.com>

=head1 LICENSE

Copyright Tom Molesworth 2011-2012. Licensed under the same terms as Perl itself.
