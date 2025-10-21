#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use JSON::PP;
use Unicode::Normalize qw(NFKC);
use URI::Escape qw(uri_escape);

binmode STDIN, ':utf8';
binmode STDOUT, ':utf8';

my $url = shift @ARGV // '';
my $json = do { local $/; <STDIN> // '' };
my $payload = {};
if (length $json) {
    eval { $payload = JSON::PP->new->utf8->decode($json); 1 } or $payload = {};
}

my $snippet = $payload->{snippet} // '';
my $context = $payload->{context} // '';

sub canonicalize {
    my ($text) = @_;
    return '' unless defined $text && length $text;
    $text = NFKC($text);
    $text =~ s/[\x00-\x1F\x7F-\x9F]//g;
    $text =~ tr/\x{201C}\x{201D}\x{201F}\x{00AB}\x{00BB}/"/;
    $text =~ tr/\x{2018}\x{2019}\x{201A}\x{201B}/'/;
    $text =~ tr/\x{2010}\x{2011}\x{2012}\x{2013}\x{2014}\x{2015}\x{2212}/-/;
    $text =~ s/\x{2026}/.../g;
    $text =~ tr/\x{00A0}\x{1680}\x{180E}\x{2000}\x{2001}\x{2002}\x{2003}\x{2004}\x{2005}\x{2006}\x{2007}\x{2008}\x{2009}\x{200A}\x{202F}\x{205F}\x{3000}/ /;
    $text =~ s/[\x{200B}\x{200C}\x{200D}\x{FEFF}]//g;
    $text =~ s/\s+/ /g;
    $text =~ s/^\s+|\s+$//g;
    return $text;
}

sub prepare_words {
    my ($text) = @_;
    my @raw = split / /, $text;
    my @words;
    for my $idx (0 .. $#raw) {
        my $word = $raw[$idx];
        $word =~ s/^[\"'\x{201C}\x{201D}\x{2018}\x{2019}\x{00AB}\x{00BB}]+//;
        $word =~ s/[\"'\x{201C}\x{201D}\x{2018}\x{2019}\x{00AB}\x{00BB},.;:!?()\[\]{}]+$//;
        next unless length $word;
        my $preferred = ($word =~ /^[A-Za-z]+$/);
        my $ascii = join('', map { lc $_ } ($word =~ /([A-Za-z]+)/g));
        push @words, {
            index     => $idx,
            text      => $word,
            preferred => $preferred,
            ascii     => $ascii,
        };
    }
    return \@words;
}

sub contiguous_segments {
    my ($words_ref, $preferred_only) = @_;
    my @segments;
    my @current;
    my $prev;
    for my $info (@$words_ref) {
        if ($preferred_only && !$info->{preferred}) {
            push @segments, [@current] if @current;
            @current = ();
            $prev = $info->{index};
            next;
        }
        if (!defined $prev || $info->{index} == $prev + 1) {
            push @current, $info;
        } else {
            push @segments, [@current] if @current;
            @current = ($info);
        }
        $prev = $info->{index};
    }
    push @segments, [@current] if @current;
    return [ grep { @$_ } @segments ];
}

sub join_words {
    my ($infos) = @_;
    return join(' ', map { $_->{text} } @$infos);
}

sub count_occurrences {
    my ($context, $phrase) = @_;
    return 1 unless length $context && length $phrase;
    my $lc_context = lc $context;
    my $lc_phrase  = lc $phrase;
    my $len        = length $lc_phrase;
    my $pos        = 0;
    my $count      = 0;
    while (1) {
        my $idx = index($lc_context, $lc_phrase, $pos);
        last if $idx == -1;
        $count++;
        $pos = $idx + $len;
    }
    return $count;
}

sub collect_context {
    my ($words_ref, $start, $len, $direction, $limit) = @_;
    $limit //= 4;
    my @collected;
    if ($direction eq 'prefix') {
        my $idx = $start - 1;
        while ($idx >= 0 && @collected < $limit) {
            my $word = $words_ref->[$idx];
            if ($word->{preferred} || $word->{ascii}) {
                unshift @collected, $word->{text};
            }
            $idx--;
        }
    } else {
        my $idx = $start + $len;
        while ($idx < @$words_ref && @collected < $limit) {
            my $word = $words_ref->[$idx];
            if ($word->{preferred} || $word->{ascii}) {
                push @collected, $word->{text};
            }
            $idx++;
        }
    }
    return join(' ', @collected);
}

$snippet = canonicalize($snippet);
$context = canonicalize($context);

if (!$snippet || $url !~ m/^https?:\/\//i || $url =~ /\.pdf(?:$|[?#])/i) {
    print $url;
    exit 0;
}

my $words = prepare_words($snippet);
if (!@$words) {
    print $url;
    exit 0;
}

my $preferred_segments = contiguous_segments($words, 1);
my $relaxed_segments   = contiguous_segments($words, 0);

my @candidates = grep { @$_ >= 5 } @$preferred_segments;
if (!@candidates) {
    @candidates = grep { @$_ >= 5 } @$relaxed_segments;
}
if (!@candidates && @$relaxed_segments) {
    @candidates = @$relaxed_segments;
}

if (!@candidates) {
    print $url;
    exit 0;
}

my $segment = $candidates[0];
my $max_len = @$segment < 8 ? scalar @$segment : 8;
my @lengths = grep { $_ <= $max_len } (8, 7, 6, 5);
@lengths = ($max_len) unless @lengths;

my ($best_start, $best_len, $best_infos, $best_occurrences);
for my $len (@lengths) {
    for my $offset (0 .. @$segment - $len) {
        my @window = @{$segment}[$offset .. $offset + $len - 1];
        my $phrase = join_words(\@window);
        next unless length $phrase;
        my $occ = count_occurrences($context, $phrase);
        ($best_start, $best_len, $best_infos, $best_occurrences) =
            ($segment->[0]{index} + $offset, $len, \@window, $occ);
        last if $occ == 1;
    }
    last if defined $best_occurrences && $best_occurrences == 1;
}

if (!defined $best_start) {
    my $len = @$segment < 6 ? scalar @$segment : 6;
    my @window = @{$segment}[0 .. $len - 1];
    my $phrase = join_words(\@window);
    ($best_start, $best_len, $best_infos, $best_occurrences) =
        ($segment->[0]{index}, $len, \@window, count_occurrences($context, $phrase));
}

my $window_phrase = join_words($best_infos // []);
if (!$window_phrase) {
    print $url;
    exit 0;
}

my $prefix_text = collect_context($words, $best_start, $best_len, 'prefix', 4);
my $suffix_text = collect_context($words, $best_start, $best_len, 'suffix', 4);

my @fragments;
if (($best_occurrences // 0) != 1 && ($prefix_text || $suffix_text)) {
    push @fragments, [$prefix_text, $window_phrase, $suffix_text];
}
push @fragments, ['', $window_phrase, ''];

if (@$best_infos > 4) {
    my $front = join_words([ @$best_infos[0 .. 3] ]);
    push @fragments, ['', $front, ''] if $front && lc($front) ne lc($window_phrase);
    my $back  = join_words([ @$best_infos[-4 .. -1] ]);
    if ($back && lc($back) ne lc($window_phrase) && (!@fragments || lc($back) ne lc($fragments[-1][1]))) {
        push @fragments, ['', $back, ''];
    }
}

my %seen;
my @encoded;
for my $frag (@fragments) {
    my ($pre, $start, $post) = @$frag;
    next unless $start;
    my $key = join("\t", map { lc($_ // '') } ($pre, $start, $post));
    next if $seen{$key}++;
    my @parts;
    push @parts, uri_escape($pre) . '-' if $pre;
    push @parts, uri_escape($start);
    push @parts, '-' . uri_escape($post) if $post;
    push @encoded, join('', @parts);
    last if @encoded >= 3;
}

if (!@encoded) {
    print $url;
    exit 0;
}

my $fragment_payload = join('&text=', @encoded);
if ($url =~ /#:~:text=/) {
    print $url . '&text=' . $fragment_payload;
} elsif ($url =~ /#/) {
    print $url . ':~:text=' . $fragment_payload;
} else {
    print $url . '#:~:text=' . $fragment_payload;
}
