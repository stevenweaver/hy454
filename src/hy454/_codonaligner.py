
from math import ceil, log
from os.path import abspath, exists, join, split
from sys import stderr

from Bio.Alphabet import generic_dna

from _hyphyinterface import HyphyInterface


__all__ = ['CodonAligner']


class CodonAligner(HyphyInterface):

    def __init__(self, batchfile=None):
        if batchfile is None:
            batchfile = join(
                    split(abspath(__file__))[0],
                    'hyphy', 'codonaligner.bf'
            )
        if not exists(batchfile):
            raise ValueError("Invalid batchfile `%s', it doesn't exist!" % batchfile)
        # use only 1 cpu
        super(CodonAligner, self).__init__(batchfile, 1)

    def align(self, refseq, seqs, quiet=True):
        # pad the reference to the nearest codon,
        # otherwise the hyphy codon alignment algo barfs 
        if len(refseq) > 3:
            pad = 3 - (len(refseq) % 3)
            pad = 0 if pad == 3 else pad
            refseq += '-' * pad
            scoremod = float(len(refseq)) / (len(refseq) - pad)
        else:
            pad = 0
            scoremod = 0.

        # compute next power of two size string for the output
        outlen = (len(refseq) + 1) * len(seqs)
        outlen = ceil(log(outlen, 2))
        outlen = int(pow(2, outlen))

        self.queuestralloc('_cdnaln_outstr', outlen)
        self.queuevar('_cdnaln_refseq', refseq)
        self.queuevar('_cdnaln_seqs', seqs)

        self.runqueue()

        if not quiet:
            if self.stdout != '':
                print >> stderr, self.stdout
            if self.warnings != '':
                print >> stderr, self.warnings

        if self.stderr != '':
            raise RuntimeError(self.stderr)

        newseqstrs = self.getvar('seqs', HyphyInterface.STRING).split(',')
        scores = self.getvar('scores', HyphyInterface.MATRIX)
        if pad:
            newseqstrs = [s[:-pad] for s in newseqstrs]
        if scoremod:
            scores = [s * scoremod for s in scores]
        return newseqstrs, scores
