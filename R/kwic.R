#' @include S4classes.R
NULL


setAs(
  from = "kwic",
  to = "htmlwidget",
  def = function(from){
    if (getOption("polmineR.lineview")){
      from@table[["node"]] <- paste('<span style="color:steelblue">', from@table[["node"]], '</span>', sep="")
      from@table[["text"]] <- apply(from@table, 1, function(x) paste(x[c("left", "node", "right")], collapse = " "))
      for (x in c("left", "node", "right", "hit_no")) from@table[[x]] <- NULL
      retval <- DT::datatable(from@table, escape = FALSE)
    } else {
      from@table[["hit_no"]] <- NULL
      retval <- DT::datatable(from@table, escape = FALSE)
      retval <- DT::formatStyle(retval, "node", color = "blue", textAlign = "center")
      retval <- DT::formatStyle(retval, "left", textAlign = "right")
    }
    retval$dependencies[[length(retval$dependencies) + 1L]] <- htmltools::htmlDependency(
      name = "tooltips", version = "0.0.0",
      src = system.file(package = "polmineR", "css"), stylesheet = "tooltips.css"
    )
    retval
  }
)

#' @rdname kwic-class
#' @docType method
#' @importFrom DT datatable formatStyle
setMethod("show", "kwic", function(object){
  retval <- as(object, "htmlwidget")
  if (interactive()) show(retval)
})


#' @rdname kwic-class
#' @docType method
#' @exportMethod as.character
#' @param fmt A format string passed into \code{sprintf} to format the node of a KWIC display.
#' @examples 
#' oil <- kwic("REUTERS", query = "oil")
#' as.character(oil)
setMethod("as.character", "kwic", function(x, fmt = "<i>%s</i>"){
  if (!is.null(fmt)) x@table[["node"]] <- sprintf(fmt, x@table[["node"]])
  apply(
    x@table, 1L,
    function(row) paste(
      row["left"],
      row["node"],
      row["right"],
      sep = " "
    )
  )
})

#' @docType methods
#' @noRd
setMethod('[', 'kwic',
          function(x,i) {
            x@table <- x@table[i,]
            x
          }        
)

#' @rdname kwic-class
setMethod("as.data.frame", "kwic", function(x){
  metaColumnsNo <- length(colnames(x@table)) - 3L
  metadata <- apply(x@table, 1, function(row) paste(row[1L:metaColumnsNo], collapse="<br/>"))
  data.frame(
    meta = metadata,
    left = x@table$left,
    node = x@table$node,
    right = x@table$right
  )
})


#' @rdname kwic-class
setMethod("length", "kwic", function(x) nrow(x@table) )

#' @rdname kwic-class
setMethod("sample", "kwic", function(x, size){
  hits_unique <- unique(x@cpos[["hit_no"]])
  if (size > length(hits_unique)){
    warning("argument size exceeds number of hits, returning original object")
    return(x)
  }
  x@cpos <- x@cpos[which(x@cpos[["hit_no"]] %in% sample(hits_unique, size = size))]
  x <- enrich(x, table = TRUE)
  x <- enrich(x, s_attributes = x@metadata)
  x
  
})


#' @include partition.R context.R
NULL 

#' KWIC/concordance output.
#' 
#' Prepare and show concordances / keyword-in-context (kwic). The same result can be achieved by 
#' applying the kwic method on either a partition or a context object.
#' 
#' If a positivelist ist supplied, the tokens will be highlighted.
#' 
#' @param .Object a \code{partition} or \code{context} object
#' @param query a query, CQP-syntax can be used
#' @param cqp either logical (TRUE if query is a CQP query), or a
#'   function to check whether query is a CQP query or not (defaults to is.query
#'   auxiliary function)
#' @param left to the left
#' @param right to the right
#' @param s_attributes Structural attributes (s-attributes) to include into output table as metainformation.
#' @param cpos logical, if TRUE, the corpus positions ("cpos") if the hits will be handed over to the kwic-object that is returned
#' @param p_attribute p-attribute, defaults to 'word'
#' @param boundary if provided, the s-attribute will be used to check the boundaries of the text
#' @param stoplist terms or ids to prevent a concordance from occurring in results
#' @param positivelist terms or ids required for a concordance to occurr in results
#' @param regex logical, whether stoplist/positivelist is processed as regular expression
#' @param verbose logical, whether to be talkative
#' @param ... further parameters to be passed
#' @rdname kwic
#' @docType methods
#' @seealso To read the whole text, see the \code{\link{read}}-method.
#' @references 
#' Baker, Paul (2006): \emph{Using Corpora in Discourse Analysis}. London: continuum, pp. 71-93 (ch. 4).
#'
#' Jockers, Matthew L. (2014): \emph{Text Analysis with R for Students of Literature}.
#' Cham et al: Springer, pp. 73-87 (chs. 8 & 9).
#' @examples
#' use("polmineR")
#' bt <- partition("GERMAPARLMINI", def = list(date = ".*"), regex = TRUE)
#' kwic(bt, "Integration")
#' kwic(bt, "Integration", left = 20, right = 20, s_attributes = c("date", "speaker", "party"))
#' kwic(
#'   bt, '"Integration" [] "(Menschen|Migrant.*|Personen)"',
#'   left = 20, right = 20,
#'   s_attributes = c("date", "speaker", "party")
#' ) 
#' @exportMethod kwic
setGeneric("kwic", function(.Object, ...) standardGeneric("kwic") )



#' @exportMethod kwic
#' @docType methods
#' @rdname kwic
setMethod("kwic", "context", function(.Object, s_attributes = getOption("polmineR.meta"), cpos = TRUE, verbose = FALSE, ...){
  
  if ("meta" %in% names(list(...))) s_attributes <- list(...)[["meta"]]
  
  DT <- copy(.Object@cpos) # do not accidentily store things
  setorderv(DT, cols = c("hit_no", "cpos"))
  decoded_pAttr <- CQI$id2str(
    .Object@corpus, .Object@p_attribute[1],
    DT[[paste(.Object@p_attribute[1], "id", sep = "_")]]
  )
  decoded_pAttr2 <- as.nativeEnc(decoded_pAttr, from = .Object@encoding)
  DT[, .Object@p_attribute[1] := decoded_pAttr2, with = TRUE]
  DT[, "direction" := sign(DT[["position"]]), with = TRUE]
  
  if (is.null(s_attributes)) s_attributes <- character()
  conc <- new(
    'kwic',
    corpus = .Object@corpus,
    left = as.integer(.Object@left),
    right = as.integer(.Object@right),
    metadata = if (length(s_attributes) == 0L) character() else s_attributes,
    encoding = .Object@encoding,
    labels = Labels$new(),
    cpos = if (cpos) DT else data.table()
  )
  
  conc <- enrich(conc, table = TRUE)
  conc <- enrich(conc, s_attributes = s_attributes)
  conc
})


#' @rdname kwic
#' @exportMethod kwic
setMethod("kwic", "partition", function(
  .Object, query, cqp = is.cqp,
  left = getOption("polmineR.left"),
  right = getOption("polmineR.right"),
  s_attributes = getOption("polmineR.meta"),
  p_attribute = "word", boundary = NULL, cpos = TRUE,
  stoplist = NULL, positivelist = NULL, regex = FALSE,
  verbose = TRUE, ...
){
  
  if ("pAttribute" %in% names(list(...))) p_attribute <- list(...)[["pAttribute"]]
  if ("sAttribute" %in% names(list(...))) boundary <- list(...)[["sAttribute"]]
  if ("sAttribute" %in% names(list(...))) boundary <- list(...)[["s_attribute"]]
  if ("meta" %in% names(list(...))) s_attributes <- list(...)[["meta"]]
  
  # the actual work is done by the kwic,context-method
  # this method prepares a context-object and applies the
  # kwic method to that object
  ctxt <- context(
    .Object = .Object, query = query, cqp = cqp,
    p_attribute = p_attribute, boundary = boundary,
    left = left, right = right,
    stoplist = stoplist, positivelist = positivelist, regex = regex,
    count = FALSE, verbose = verbose
  )
  if (is.null(ctxt)){
    message("... no occurrence of query")
    return(invisible(NULL))
  }
  retval <- kwic(.Object = ctxt, s_attributes = s_attributes, cpos = cpos)
  if (!is.null(positivelist)){
    retval <- highlight(retval, highlight = list(yellow = positivelist), regex = regex)
  }
  retval
})


#' @rdname kwic
setMethod("kwic", "character", function(
  .Object, query, cqp = is.cqp,
  left = as.integer(getOption("polmineR.left")),
  right = as.integer(getOption("polmineR.right")),
  s_attributes = getOption("polmineR.meta"),
  p_attribute = "word", boundary = NULL, cpos = TRUE,
  stoplist = NULL, positivelist = NULL, regex = FALSE,
  verbose = TRUE, ...
){
  
  if ("pAttribute" %in% names(list(...))) p_attribute <- list(...)[["pAttribute"]]
  if ("sAttribute" %in% names(list(...))) boundary <- list(...)[["sAttribute"]]
  if ("s_attribute" %in% names(list(...))) boundary <- list(...)[["s_attribute"]]
  if ("meta" %in% names(list(...))) s_attributes <- list(...)[["meta"]]
  
  hits <- cpos(.Object, query = query, cqp = cqp, p_attribute = p_attribute, verbose = FALSE)
  if (is.null(hits)){
    message("sorry, not hits");
    return(invisible(NULL))
  }
  cpos_max <- CQI$attribute_size(.Object, p_attribute, type = "p")
  cposList <- apply(
    hits, 1,
    function(row){
      left <- c((row[1] - left - 1L):(row[1] - 1L))
      right <- c((row[2] + 1L):(row[2] + right + 1L))
      list(
        left = left[left > 0L],
        node = c(row[1]:row[2]),
        right = right[right <= cpos_max]
      )
    }
  )
  DT <- data.table(
    hit_no = unlist(lapply(1L:length(cposList), function(i) rep(i, times = length(unlist(cposList[[i]]))))),
    cpos = unname(unlist(cposList)),
    position = unlist(lapply(
      cposList,
      function(x) lapply(
        names(x),
        function(x2)
          switch(
            x2,
            left = rep(-1L, times = length(x[[x2]])),
            node = rep(0L, times = length(x[[x2]])),
            right = rep(1L, times = length(x[[x2]])))
      )))
  )
  DT[[paste(p_attribute, "id", sep = "_")]] <- CQI$cpos2id(.Object, p_attribute, DT[["cpos"]])
  
  ctxt <- new(
    Class = "context",
    query = character(),
    count = nrow(hits),
    stat = data.table(),
    corpus = .Object,
    size_partition = integer(),
    size = integer(),
    left = as.integer(left),
    right = as.integer(right), 
    cpos = DT,
    boundary = character(),
    p_attribute = p_attribute,
    encoding = registry_get_encoding(.Object),
    partition = new("partition", stat = data.table())
  )
  
  # generate positivelist/stoplist with ids and apply it
  if (!is.null(positivelist)) ctxt <- trim(ctxt, positivelist = positivelist, regex = regex, verbose = verbose)
  if (!is.null(stoplist)) ctxt <- trim(ctxt, stoplist = stoplist, regex = regex, verbose = verbose)
  
  if (!is.null(boundary)) ctxt@boundary <- boundary
  kwic(.Object = ctxt, s_attributes = s_attributes, cpos = cpos)
})
