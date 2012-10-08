/*---------------------------------------------
 reverse complement a nucleotide string
---------------------------------------------*/

_revcomp_map = {};
_revcomp_map["A"] = "T";
_revcomp_map["C"] = "G";
_revcomp_map["G"] = "C";
_revcomp_map["T"] = "A";
_revcomp_map["M"] = "K";
_revcomp_map["R"] = "Y";
_revcomp_map["W"] = "W";
_revcomp_map["S"] = "S";
_revcomp_map["Y"] = "R";
_revcomp_map["K"] = "M";
_revcomp_map["B"] = "V";  /* not A */
_revcomp_map["D"] = "H";  /* not C */
_revcomp_map["H"] = "D";  /* not G */
_revcomp_map["V"] = "B";  /* not T */
_revcomp_map["N"] = "N";

function RevComp( _seq )
{
    _seqL = Abs( _seq );
    _seq2 = "";
    _seq2 * 128;
    _seqL += -1;
	for ( _rcidx = _seqL; _rcidx >= 0; _rcidx += -1 )
	{
		_seq2 * _revcomp_map[ _seq[ _rcidx ] && 1 ];
	}
	_seq2 * 0;
	return _seq2;
}

function Uppercase( _str )
{
    _upstr = _str && 1;
    _upstr * 0;
    return _upstr;
}

function TrimStop( _seq )
{
    _seq2 = _seq  ^ {{ "[-]$", "" }};
    _seq2 = _seq2 ^ {{ "[Tt][Aa][Aa]$", "" }};
    _seq2 = _seq2 ^ {{ "[Tt][Aa][Gg]$", "" }};
    _seq2 = _seq2 ^ {{ "[Tt][Gg][Aa]$", "" }};
    return _seq2;
}

function CleanAlignment( _aln, _keepIns )
/*
 * Given the raw alignment record from AlignSequence, clean the aligned sequence and return either the raw sequence or the list of positions by CSV
 * @param  _aln 		-- the alignment dictionary
 * @param  _keepIns 	-- whether or not to keep insertions in the REFERENCE (0/1)
 * @return the cleaned string
 */
{
    _ref = ( _aln[0] )[1];
    _seq = ( _aln[0] )[2];
    _altRef = _ref ^ {{ "[a-z]", "_" }};
    _newRef = "";
    _newStr = "";
    _newRef * 256;
    _newStr * 256;
    if ( _keepIns ) {
        _keepIns = 1;
    } else {
        _keepIns = 0;
    }
    _k = 0;
    _overlap_count = 0;

    // codon by codon...
    _nucLen = Abs( _ref ^ {{ "[-]", "" }} );
    for ( _l = 0; _l < _nucLen; _l += 3 ) {
        _ins = 0;
        _dels = 0;
        // count the number of insertions and deletions
        _cdnAdv = Min( 3, _nucLen - _l );
        for ( _k2 = 0; _k2 < _cdnAdv; _k2 += 1 ) {
            if ( _altRef[ _k+_k2 ] == "-" ) {
                _ins += 1;
            } else {
                if ( _altRef[ _k+_k2 ] == "_" ) {
                    _dels += 1;
                }
            }
        }
        // if _ins == 3 (and we want to keep inserts),
        // then we have a full codon insertion,
        // add the original characters back in
        // if _ins == 0 and _dels == 0, then everything is normal,
        // add the original characters back in
        if ( ( _keepIns * _ins ) == 3 || ( _ins == 0 && _dels == 0 ) ) {
            _newRef * _ref[ _k ][ _k+2 ];
            _newStr * _seq[ _k ][ _k+2 ];

            _overlap_count += 3 * ( _seq[ _k ][ _k+2 ] != "---" );
            
            _k += 3;
        }
        // if neither of those two cases is true, then we need to go
        // position by position, removing insertions and
        // fixing deletions by adding in a "N"
        else {
            // _k2 advances by only a single codon (3 positions), whereas
            // _l2 moves us ahead in the alignment. At the end, the difference
            // between _k2 and _l2 should be that _l2 is greater by the number
            // of inserted nucleotides
            _k2 = 0;
            for ( _l2 = 0; _k2 < _cdnAdv; _l2 += 1 ) {
                // "_" means a deletion, add an "N" back in
                if ( _altRef[ _k+_l2 ] == "_" ) {
                    _newRef * _ref[ _k+_l2 ];
                    _newStr * "-"; // we used to add an N here, but that was controversial

                    _k2 += 1;
                }
                // if the character isn't an insertion
                // which it always isn't because we took care of
                // insertions above, add the original back in
                else {
                    if ( _altRef[ _k+_l2 ] != "-" ) {
                        _newRef * _ref[ _k+_l2 ];
                        _newStr * _seq[ _k+_l2 ];

                        _overlap_count += ( _seq[ _k+_l2 ] != "-" );
                        
                        _k2 += 1;
                    }
                }
            }
            _k += _l2;
        }
    }
    // only uppercase when not keeping inserts
    if ( _keepIns ) {
        _rest = Abs( _seq ) - _k;
        for ( _k2 = 0; _k2 < _rest; _k2 += 1 ) {
            _newRef * "-";
            _newStr * _seq[ _k+_k2 ];
        }
    } else {
        _newRef = Uppercase( _newRef );
        _newStr = Uppercase( _newStr );
    }
    _newRef * 0;
    _newStr * 0;
    // get rid of any gaps
    // _newStr2 = _newStr^{{"[-]", ""}};
    return { "ref": _newRef, 
             "seq": _newStr, 
             "overlap": _overlap_count / 3 };
}

function pSM2cSM(_scorematrix, _letters)
{
    LoadFunctionLibrary( "chooseGeneticCode", { "00": "Universal" } );
    LoadFunctionLibrary( "GrabBag" );

    _cdnScoreMatrix  = { 65,65 };
    _mapping      = mapStrings( _hyphyAAOrdering, _letters );
    for ( _k = 0; _k < 64; _k += 1 ) {
        _mappedK = _mapping[ _Genetic_Code[ _k ] ];
        if ( _mappedK >= 0) {
            for ( _k2 = _k; _k2 < 64; _k2 += 1 ) {
                _mappedK2 = _mapping[ _Genetic_Code[ _k2 ] ];
                if ( _mappedK2 >= 0 ) {
                    _aScore = _scorematrix[ _mappedK ][ _mappedK2 ];
                    if ( _mappedK == _mappedK2 && _k2 > _k ) {
                        _aScore = _aScore - 1;
                    }
                } else {
                    // stop codons don't match anything
                    _aScore = -1e4;
                }
                _cdnScoreMatrix[ _k ][ _k2 ] = _aScore;
                _cdnScoreMatrix[ _k2 ][ _k ] = _aScore;
            }
        } else {
            for ( _k2 = _k; _k2 < 64; _k2 += 1 ) {
                _mappedK2 = _mapping[ _Genetic_Code[ _k2 ] ];
                if ( _mappedK2 < 0 ) {
                    // don't penalize stop codons matching themselves
                    _cdnScoreMatrix[ _k ][ _k2 ] = 0;
                    _cdnScoreMatrix[ _k2 ][ _k ] = 0;
                } else {
                    _cdnScoreMatrix[ _k ][ _k2 ] = -1e4;
                    _cdnScoreMatrix[ _k2 ][ _k ] = -1e4;
                }
            }
        }
    }

    return _cdnScoreMatrix;
}

function cSM2partialSMs(_cdnScoreMatrix)
{
    m3x5  =  { 65, 640 };
    m3x4  =  { 65, 256 };
    m3x2  =  { 65,  48 };
    m3x1  =  { 65,  12 };

    // minor penalties to make mismatch not entirely free
    p3x5 = 2*p3x4;;
    p3x4 = 1;
    p3x2 = 1;
    p3x1 = 2*p3x2;

    for ( thisCodon = 0; thisCodon < 64; thisCodon += 1 ) {
        for ( d1 = 0; d1 < 4; d1 += 1 ) {
            max100 = -1e100;
            max010 = -1e100;
            max001 = -1e100;

            for ( d2 = 0; d2 < 4; d2 += 1 ) {
                partialCodon = 4 * d1 + d2;
                max110 = -1e100;
                max101 = -1e100;
                max011 = -1e100;

                for ( d3 = 0; d3 < 4; d3 += 1 ) {
                    thisCodon2 = 4 * partialCodon + d3;
                    thisScore = _cdnScoreMatrix[ thisCodon ][ thisCodon2 ];

                    // this is the trivial and stupid way of doing it, but it should work
                    m3x5[ thisCodon ][ 10 * thisCodon2 + 0 ] = thisScore - p3x5;
                    m3x5[ thisCodon ][ 10 * thisCodon2 + 1 ] = thisScore - p3x5;
                    m3x5[ thisCodon ][ 10 * thisCodon2 + 2 ] = thisScore - p3x5;
                    m3x5[ thisCodon ][ 10 * thisCodon2 + 3 ] = thisScore - p3x5;
                    m3x5[ thisCodon ][ 10 * thisCodon2 + 4 ] = thisScore - p3x5;
                    m3x5[ thisCodon ][ 10 * thisCodon2 + 5 ] = thisScore - p3x5;
                    m3x5[ thisCodon ][ 10 * thisCodon2 + 6 ] = thisScore - p3x5;
                    m3x5[ thisCodon ][ 10 * thisCodon2 + 7 ] = thisScore - p3x5;
                    m3x5[ thisCodon ][ 10 * thisCodon2 + 8 ] = thisScore - p3x5;
                    m3x5[ thisCodon ][ 10 * thisCodon2 + 9 ] = thisScore - p3x5;

                    m3x4[ thisCodon ][ 4 * thisCodon2 + 0 ] = thisScore - p3x4;
                    m3x4[ thisCodon ][ 4 * thisCodon2 + 1 ] = thisScore - p3x4;
                    m3x4[ thisCodon ][ 4 * thisCodon2 + 2 ] = thisScore - p3x4;
                    m3x4[ thisCodon ][ 4 * thisCodon2 + 3 ] = thisScore - p3x4;

                    // d1 is 1
                    max100 = Max( max100, _cdnScoreMatrix[ thisCodon ][ 16 * d1 + 4 * d2 + d3 ] );
                    max010 = Max( max010, _cdnScoreMatrix[ thisCodon ][ 16 * d2 + 4 * d1 + d3 ] );
                    max001 = Max( max001, _cdnScoreMatrix[ thisCodon ][ 16 * d2 + 4 * d3 + d1 ] );

                    // d1 and d2 are 1
                    max110 = Max( max110, _cdnScoreMatrix[ thisCodon ][ 16 * d1 + 4 * d2 + d3 ] );
                    max101 = Max( max101, _cdnScoreMatrix[ thisCodon ][ 16 * d1 + 4 * d3 + d2 ] );
                    max011 = Max( max011, _cdnScoreMatrix[ thisCodon ][ 16 * d3 + 4 * d1 + d2 ] );
                }

                m3x2[ thisCodon ][ 3 * partialCodon + 0 ] = max110 - p3x2;
                m3x2[ thisCodon ][ 3 * partialCodon + 1 ] = max101 - p3x2;
                m3x2[ thisCodon ][ 3 * partialCodon + 2 ] = max011 - p3x2;
            }

            m3x1[ thisCodon ][ 3 * d1 + 0 ] = max100 - p3x1;
            m3x1[ thisCodon ][ 3 * d1 + 1 ] = max010 - p3x1;
            m3x1[ thisCodon ][ 3 * d1 + 2 ] = max001 - p3x1;
        }
    }
    return { "3x1": m3x1, "3x2": m3x2, "3x4": m3x4, "3x5": m3x5 };
}

// -------------------------------------------------------------------------- //

function computeExpectedPerBaseScore( _expectedIdentity ) {
    meanScore = 0;

    for (_aa1 = 0; _aa1 < 20; _aa1 += 1) {
        for (_aa2 = 0; _aa2 < 20; _aa2 += 1) {
            if ( _aa1 != _aa2 ) {
                meanScore += ( 1 - _expectedIdentity ) * _cdnaln_scorematrix[_aa1][_aa2] * _cdnaln_base_freqs[_aa1] * _cdnaln_base_freqs[_aa2] * _cdnaln_pair_norm;
            } else {
                meanScore += _expectedIdentity * _cdnaln_scorematrix[_aa1][_aa1] * _cdnaln_base_freqs[_aa1];
            }
        }
    }

    return meanScore;
}


// -------------------------------------------------------------------------- //
// ---------------------------- BEGIN MAIN ---------------------------------- //
// -------------------------------------------------------------------------- //



_cdnaln_base_freqs = {
{0.060490222}
{0.020075899}
{0.042109048}
{0.071567447}
{0.028809447}
{0.072308239}
{0.022293943}
{0.069730629}
{0.056968211}
{0.098851122}
{0.019768318}
{0.044127815}
{0.046025282}
{0.053606488}
{0.066039665}
{0.050604330}
{0.053636813}
{0.061625237}
{0.033011601}
{0.028350243}
};

_cdnaln_pair_norm = 0;
for ( _aa1 = 0; _aa1 < 20; _aa1 += 1 ) {
    _cdnaln_pair_norm += _cdnaln_base_freqs[ _aa1 ] * _cdnaln_base_freqs[ _aa1 ]; 
}
_cdnaln_pair_norm = 1 / ( 1 - _cdnaln_pair_norm );

ChoiceList ( _cdnaln_dorevcomp, "Align reverse complement?", 1, SKIP_NONE,
             "No", "Do not check reverse complement",
             "Yes", "Check reverse complement" );

ChoiceList ( _cdnaln_keepins, "Keep insertions?", 1, SKIP_NONE,
             "No", "Do not keep insertions",
             "Yes", "Keep insertions" );

// fprintf( stdout, "Please provide the reference sequence: " );
fscanf( stdin, "String", _cdnaln_refseq );
// fprintf( stdout, "Please provide the expected identity: " );
fscanf( stdin, "Number", _cdnaln_expected_identity );
// fprintf( stdout, "Please provide the number of query sequences: " );
fscanf( stdin, "Number", _cdnaln_numseqs );
_cdnaln_seqs = {};

for ( _cdnaln_idx = 0; _cdnaln_idx < _cdnaln_numseqs; _cdnaln_idx += 1 ) {
    // fprintf( stdout, "Please provide query sequence no. " + ( _cdnaln_idx + 1 ) + ": " );
    fscanf( stdin, "String", _cdnaln_grabseq );
    _cdnaln_seqs[ _cdnaln_idx ] = _cdnaln_grabseq;
}

// uppercase and gapless
_cdnaln_refseq = Uppercase( _cdnaln_refseq ^ {{ "[-]", "" }} );
for ( _cdnaln_idx = 0; _cdnaln_idx < _cdnaln_numseqs; _cdnaln_idx += 1 ) {
    _cdnaln_seqs[ _cdnaln_idx ] = Uppercase( _cdnaln_seqs[ _cdnaln_idx ] ^ {{ "[-]", "" }} );
}

// Due to some bugs in the implementation of the codon aligner,
// pad the reference sequence to a multiple of 3,
_cdnaln_truelen = Abs( _cdnaln_refseq );
_cdnaln_pad = 3 - ( _cdnaln_truelen % 3 );
if ( _cdnaln_pad > 0 && _cdnaln_pad < 3 ) {
    _cdnaln_refseq * ( "NN"[ 0 ][ ( _cdnaln_pad - 1 ) ] );
}
_cdnaln_refseq * 0;
_cdnaln_scoremod = _cdnaln_truelen / ( _cdnaln_truelen + _cdnaln_pad );

_cdnaln_cdnScoreMatrix = pSM2cSM(_cdnaln_scorematrix, _cdnaln_letters);

_cdnaln_alnopts = {};
_cdnaln_alnopts ["SEQ_ALIGN_SCORE_MATRIX"] = _cdnaln_cdnScoreMatrix;
_cdnaln_alnopts ["SEQ_ALIGN_GAP_OPEN"] = -2.5 * Min( _cdnaln_scorematrix, 0 );
_cdnaln_alnopts ["SEQ_ALIGN_AFFINE"] = 1;
_cdnaln_alnopts ["SEQ_ALIGN_GAP_OPEN2"] = -1.5 * Min( _cdnaln_scorematrix, 0 );
_cdnaln_alnopts ["SEQ_ALIGN_GAP_EXTEND2"] = 1;
_cdnaln_alnopts ["SEQ_ALIGN_GAP_EXTEND"] = 1;
_cdnaln_alnopts ["SEQ_ALIGN_FRAMESHIFT"] = -Min( _cdnaln_scorematrix, 0 );
_cdnaln_alnopts ["SEQ_ALIGN_CODON_ALIGN"] = 1;
_cdnaln_alnopts ["SEQ_ALIGN_NO_TP"] = 1; // this means local alignment, apparently
_cdnaln_alnopts ["SEQ_ALIGN_CHARACTER_MAP"] = "ACGT";

_cdnaln_partialScoreMatrices = cSM2partialSMs(_cdnaln_cdnScoreMatrix);

_cdnaln_alnopts ["SEQ_ALIGN_PARTIAL_3x1_SCORES"] = _cdnaln_partialScoreMatrices["3x1"];
_cdnaln_alnopts ["SEQ_ALIGN_PARTIAL_3x2_SCORES"] = _cdnaln_partialScoreMatrices["3x2"];
_cdnaln_alnopts ["SEQ_ALIGN_PARTIAL_3x4_SCORES"] = _cdnaln_partialScoreMatrices["3x4"];
_cdnaln_alnopts ["SEQ_ALIGN_PARTIAL_3x5_SCORES"] = _cdnaln_partialScoreMatrices["3x5"];

_cdnaln_outstr = "";
_cdnaln_outstr * 256;
_cdnaln_outstr = "[";
// _cdnaln_scores = { 1, Abs( _cdnaln_seqs ) };

// if the expected_identity score is 0, then don't compute identity scores
_cdnaln_expected_identity_score = 0;
if ( _cdnaln_expected_identity > 0 ) {
    _cdnaln_expected_identity_score = computeExpectedPerBaseScore( _cdnaln_expected_identity );
}

// fprintf( stdout, "" + _cdnaln_numseqs + "\n" );

for ( _cdnaln_idx = 0; _cdnaln_idx < _cdnaln_numseqs; _cdnaln_idx += 1 )
{
    // get the input sequence length, so we can normalize the score later
    _cdnaln_seqlen = Abs( _cdnaln_seqs[ _cdnaln_idx ] ) / 3;
    // align the sequences and get the score
    _cdnaln_inseqs = {{ _cdnaln_refseq, _cdnaln_seqs[ _cdnaln_idx ] }};
    AlignSequences ( _cdnaln_alnseqs, _cdnaln_inseqs, _cdnaln_alnopts );
    // fprintf( stdout, "\n" + ( _cdnaln_alnseqs[0] )[1] + "\n" + ( _cdnaln_alnseqs[0] )[2] + "\n" );
    // divide the score by the length of the input sequence (which is assumed to be gapless)
    _cdnaln_score = ( _cdnaln_alnseqs[0] )[0] / _cdnaln_seqlen;
    if ( _cdnaln_dorevcomp ) {
        // if we are going to check the reverse complement:
        // once again align the sequences ( this time with the reverse complement )

        _cdnaln_inseqs_rc = {{ _cdnaln_refseq, RevComp( _cdnaln_seqs[ _cdnaln_idx ] ) }};
        AlignSequences( _cdnaln_alnseqs_rc, _cdnaln_inseqs_rc, _cdnaln_alnopts );
        // divide the score by the length of the input sequence (which is assumed to be gapless)
        _cdnaln_score_rc = ( _cdnaln_alnseqs_rc[0] )[0] / _cdnaln_seqlen;
        if ( _cdnaln_score_rc > _cdnaln_score ) {
            // if the reverse complement score is greater than the regular score, use it instead
            _cdnaln_cleanseqs = CleanAlignment( _cdnaln_alnseqs_rc, _cdnaln_keepins );
            _cdnaln_score = _cdnaln_score_rc;
        } else {
            // otherwise just the regular score
            _cdnaln_cleanseqs = CleanAlignment( _cdnaln_alnseqs, _cdnaln_keepins );
        }
    } else {
        // if we are not checking the reverse complement, just score the result
        _cdnaln_cleanseqs = CleanAlignment( _cdnaln_alnseqs, _cdnaln_keepins );
    }

    // trim the sequence back to the true length (unpadded) if we're not keeping insertions
    // and modify the alignment score to account for this
    _cdnaln_cleanref = _cdnaln_cleanseqs[ "ref" ];
    _cdnaln_cleanseq = _cdnaln_cleanseqs[ "seq" ];
    if ( ! _cdnaln_keepins )
    {
        _cdnaln_cleanseq = _cdnaln_cleanseq[ 0 ][ ( _cdnaln_truelen - 1 ) ];
    }
    _cdnaln_score = _cdnaln_score * _cdnaln_scoremod;

    if (_cdnaln_idx > 0)
    {
        _cdnaln_outstr * ",";
    }
    _cdnaln_identity_score = _cdnaln_score - _cdnaln_expected_identity_score;
    _cdnaln_outstr * ( "[\"" + _cdnaln_cleanref + "\",\"" + _cdnaln_cleanseq + "\"," + _cdnaln_score + "," + _cdnaln_cleanseqs["overlap"] + "," + _cdnaln_identity_score + "]" );
}

_cdnaln_outstr * "]";
_cdnaln_outstr * 0;

