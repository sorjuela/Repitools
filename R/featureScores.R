setOldClass("AffymetrixCelSet")

setGeneric("featureScores", signature = c("x", "anno"), function(x, anno, ...)
                                           {standardGeneric("featureScores")})
setGeneric(".featureScores", signature = c("x", "y"), function(x, y, ...)
                                           {standardGeneric(".featureScores")})

setClassUnion(".SequencingData", c("character", "GRanges", "GRangesList"))

setMethod(".featureScores", c("GRanges", ".CoverageSamples"),
    function(x, y, anno, up, down, dist, freq, s.width, adj.par.index = 1, map.cutoff,
             use.strand = FALSE, verbose)
{
    # Unpack variables in y.
    pos.labels <- y@pos.labels
    cvg.samps <- y@cvg.samps
    if(use.strand == FALSE)
        strand(cvg.samps) <- '*'

    # Only use sequencing data on annotated chromosomes.
    x <- x[seqnames(x) %in% seqlevels(anno)]
    seqlevels(x) <- seqlevels(anno)

    # Qualitatively near identical to running mean smoothing.
    if(verbose) message("Extending all reads to smoothing width of ", s.width[adj.par.index])
    seqlengths(x) <- rep(NA, length(seqlengths(x)))
    if(!is.null(s.width[adj.par.index]))
        x <- resize(x, s.width[adj.par.index])

    # Get coverage.
    if(verbose) message("Calculating coverage at sample points.")
    # Scale coverages for total reads.
    cvg.mat <- matrix(countOverlaps(cvg.samps, x) / length(x),
                      ncol = length(pos.labels),
                      byrow = TRUE)

    map.sample <- y@marks.samps.map[[adj.par.index]]
    if(!is.null(map.sample))
    {
        if(verbose)
            message("Scaling coverage for mappability.")
        # Scale for mappability, and make NA any regions that are below the cutoff
        cvg.mat[map.sample < map.cutoff] <- NA
        cvg.mat <- cvg.mat * 1 / map.sample
    }

    # Precision sometimes means 0 is represented as very small negative numbers.
    cvg.mat[cvg.mat < 0] = 0
    	
    colnames(cvg.mat) <- pos.labels
    rownames(cvg.mat) <- .getNames(anno)

    new("ScoresList", names = "Undefined", scores = list(cvg.mat), anno = anno,
         up = up, down = down, dist = dist, freq = freq, s.width = s.width[adj.par.index],
         .samp.info = y)
})

setMethod(".featureScores", c("GRangesList", ".CoverageSamples"),
    function(x, y, anno, up, down, dist, freq, s.width, ..., verbose)
{
    scores <- mapply(function(z, i)
	           {
                        if(verbose && !is.null(names(x)))
                            message("Processing sample ", names(x)[i])
		   	.featureScores(z, y, anno, up, down, dist,
                                        freq, s.width, i, ..., verbose = verbose)
		   }, x, IntegerList(as.list(1:length(x))), SIMPLIFY = FALSE)

    if(!is.null(names(x)))
	names <- names(x)
    else
	names <- unname(sapply(scores, names))
    new("ScoresList", names = names, anno = anno, scores = unname(sapply(scores, tables)),
                            up = up, down = down, dist = dist, freq = freq,
                            s.width = s.width, .samp.info = y)
})

setMethod(".featureScores", c("character", ".CoverageSamples"),
    function(x, y, anno, up, down, dist, freq, s.width, ..., verbose)
{
    scores <- mapply(function(z, i)
	           {
                        if(verbose && !is.null(names(x)))
                            message("Processing sample ", names(x)[i])
		   	
		   	.featureScores(BAM2GRanges(z), y, anno, up, down, dist, freq,
                                        s.width, i, ..., verbose = verbose)
		   }, x, 1:length(x), SIMPLIFY = FALSE)
    if(!is.null(names(x)))
	names <- names(x)
    else
	names <- unname(sapply(scores, names))
    new("ScoresList", names = names, anno = anno, scores = unname(sapply(scores, tables)),
                            up = up, down = down, dist = dist, freq = freq,
                            s.width = s.width, .samp.info = y)
})

setMethod(".featureScores", c(".SequencingData", "GRanges"),
    function(x, y, up, down, dist = c("base", "percent"), freq, s.width = NULL, mappability = NULL,
             map.cutoff = 0.5, tag.len = NULL, ..., verbose = TRUE)
{
    dist <- match.arg(dist)

    if(is.null(s.width) && !is.null(mappability) && is.null(tag.len))
        stop("'mappability' provided. Provide one of either 's.width' or 'tag.len'.")

    if(is.null(mappability))
        warning("Genome mappability not provided. Positions of no signal could",
                "\nbe due to being in unmappable regions of the genome.")

    if(length(s.width) == 1)
        s.width <- rep(s.width, length(x))

    str <- strand(y)
    st <- start(y)
    en <- end(y)	
    wd <- width(y) 
    pos <- str == '+'

    if(verbose) message("Calculating sampling positions.")
    cov.winds <- featureBlocks(y, up, down, dist, keep.strand = TRUE)

    posns <- seq(-up, down, freq)
    if(dist == "percent")
	pos.labels <- paste(posns, '%')
    else
	pos.labels <- posns
    n.pos <- length(posns)

    # Make ranges for each sample point.
    cvg.samps <- rep(cov.winds, each = n.pos)
    if(dist == "percent")
        gap.size <- width(cvg.samps) / (n.pos - 1)
    else
        gap.size <- rep(freq, length(cvg.samps))

    ranges(cvg.samps) <- IRanges(start = as.numeric(
                              ifelse(strand(cvg.samps) %in% c('+', '*'), 
                                     start(cvg.samps) + 0:(n.pos - 1) * gap.size,
                                     end(cvg.samps) - 0:(n.pos - 1) * gap.size)
                                                   ),
                                     width = 1)

    marks.samps.map <- NULL
    if(!is.null(mappability))
    {
        
        if(length(tag.len) == 1 & length(x) > 1)
            tag.len <- rep(tag.len, length(x))
        if(length(mappability) == 1 || class(mappability) == "BSgenome")
            mappability <- replicate(length(x), mappability)
        tag.winds <- if(is.null(s.width)) tag.len else s.width
        map.names <- sapply(mappability, function(x) x@seqs_pkgname)
        read.lengths <- sapply(map.names, function(x)
                                          {
                                              bp.loc <- regexpr("[0-9]+bp", x)
                                              substr(x, bp.loc, (bp.loc + attr(bp.loc, "match.length") - 3))
                                          })
        frags.smooths <- factor(paste(read.lengths, tag.winds, sep = '.'))
        marks.samps.map <- lapply(levels(frags.smooths), function(x)
                           {
                                frag.smooth <- as.numeric(strsplit(x, '\\.')[[1]])
                                if(verbose)
                                    message("Calculating mappability for fragment length ",
                                             frag.smooth[1], " and smoothing width ", frag.smooth[2])
                                cvg.proxim <- resize(cvg.samps, frag.smooth[2] * 2, fix = "center")
                                m.scores <- mappabilityCalc(cvg.proxim, mappability[[match(x, frags.smooths)]], verbose = FALSE)
                                matrix(m.scores, ncol = n.pos, byrow = TRUE)
                           })

        marks.samps.map <- marks.samps.map[match(frags.smooths, levels(frags.smooths))]
    }

    samp.info <- new(".CoverageSamples", pos.labels = pos.labels, cvg.samps = cvg.samps,
                     marks.samps.map = marks.samps.map)

    .featureScores(x, samp.info, y, up, down, dist, freq, s.width, map.cutoff = map.cutoff,
                   ..., verbose = verbose)
})

setMethod(".featureScores", c("matrix", "GRanges"),
    function(x, y, up, down, p.anno, mapping = NULL, freq, log2.adj = TRUE, verbose = TRUE)
{
    if(is.null(p.anno))
        stop("Probe annotation not given.")
    if(is.null(freq))
        stop("Sampling frequency not given.")

    if(is.null(mapping))
    {
        if(!"index" %in% colnames(p.anno)) p.anno[, "index"] <- 1:nrow(p.anno)
        ind.col <- colnames(p.anno) == "index"
        mapping <- annotationLookup(p.anno[, !ind.col], y, up, down, verbose)
        p.used <- unique(unlist(mapping$indexes, use.names = FALSE))
        p.anno <- p.anno[p.used, ]
        mapping <- annotationLookup(p.anno[, !ind.col], y, up, down, verbose)
        intens <- x[p.anno$index, , drop = FALSE]
    } else {
        intens <- x
    }

    if(log2.adj) intens <- log2(intens)

    points.probes <- makeWindowLookupTable(mapping$indexes, mapping$offsets,
                     starts = seq(-up, down - freq, freq),
                     ends = seq(-up + freq, down, freq))

    points.intens <- lapply(1:ncol(x), function(z)
                     {
                         .scoreIntensity(points.probes, intens[, z], returnMatrix = TRUE)
                     })    

    new("ScoresList", names = colnames(x), anno = y, scores = points.intens,
                            up = up, down = down, dist = "base", freq = freq,
                            s.width = NULL)
})

setMethod(".featureScores", c("AffymetrixCelSet", "GRanges"),
    function(x, y, p.anno = NULL, mapping = NULL, chrs = NULL, ...)
{
    if(is.null(mapping) && is.null(p.anno))
        p.anno <- getProbePositionsDf(getCdf(x), chrs, verbose = verbose)

    if(length(intersect(p.anno$chr, seqlevels(y))) == 0)
        stop("Chromosome names of probe annotation are all different to ", 
             "chromosome names of the feature annotation. Provide a mapping ", 
             "with the 'chrs' argument.")

    intens <- extractMatrix(x, cells = p.anno$index, verbose = verbose)
    p.anno$index <- 1:nrow(p.anno)

    .featureScores(intens, y, p.anno = p.anno, mapping = mapping, ...)
})

setMethod("featureScores", c("ANY", "GRanges"), function(x, anno,
           up = NULL, down = NULL, ...)
{
    invisible(.validate(anno, up, down))
    .featureScores(x, anno, up = up, down = down, ...)
})

setMethod("featureScores", c("ANY", "data.frame"),
    function(x, anno, ...)
{
    featureScores(x, annoDF2GR(anno), ...)
})
