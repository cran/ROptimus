################################################################################
#                                                                              #
#      Monte Carlo optimiser with Acceptance Ratio Simulated Annealing         #
#        featuring:                                                            #
#        * an automatic adaptive pseudo-temperature bath control;              #
#        * memory friendly processing capability;                              #
#        * progress visualisation;                                             #
#        * multi-core = multi-replica optimisation.                            #
#                                                                              #
#*******************************************************************************
#-- NUMITER = 1000000        # Number of model optimisation steps.
#-- CYCLES  = 10             # Number of annealing cycles (NUMITER should be
#                              divisible by this number).
#*******************************************************************************
#-- ACCRATIO.IN  = 90        # Initial acceptance ratio (%) at the beginning of
#                              each constituent annealing cycles.
#-- ACCRATIO.FIN = 0.5       # Final acceptance ratio (%) at the end of each
#                              constituent annealing cycles.
#-- STATWINDOW   = 70        # Number of last ongoing iterations to calculate
#                              acceptance ratio for temperature auto-adjustment.
#*******************************************************************************
#-- T.INI     = 0.00001      # Initial temperature (K) for Metropolis criterion.
#-- T.ADJSTEP = 0.000000005  # Temperature change step-size for temperature
#                              auto-adjustment based on the actual acceptance
#                              ratio.
#-- TSCLnum   = 2            # Cutoff for one of the NumofAccRatSMIdeal and
#                              NumofAccRatGRIdeal numbers after which the
#                              adjustment step is multiplied by T.SCALING.
#-- T.SCALING = 3            # See above.
#-- T.MIN     = 0.000000005  # Value to which the pseudo-temperature is set when
#                              the temperatures control unit makes T negative.
#-- T.DELTA   = 2            # Minimum value by which acceptance ratio in a
#                              STATWINDOW must differ from the ideal acceptance
#                              ratio for the temperature control unit to make a
#                              temperature adjustment.
#*******************************************************************************
#-- DUMP.FREQ = 10000        # The frequency (in steps) of writing the found
#                              ongoing best model.
#*******************************************************************************
#-- LIVEPLOT      = TRUE     # Plotting the optimisation process in a pdf file.
#-- LIVEPLOT.FREQ = 100000   # Frequency (in steps) of plotting the results.
#-- PDFheight     = 29       # Plot height in inches.
#-- PDFwidth      = 20       # Plot width in inches.
#*******************************************************************************
#-- NCPU    = 4              # Number of CPU cores to use, by running more
#                              replicas of the optimisation. The usage of more
#                              than 1 cores will attempt to load the foreach
#                              and doParallel libraries.
#-- LONG    = TRUE           # If TRUE, it means that a long simulation is
#                              expected to be done, hence the memory-friendly
#                              mode will be activated.
#-- SEED    = 840            # Setting the seed for the random number generator.
#-- OPTNAME = ""             # The name of the optimisation process.
#*******************************************************************************
#-- K.INITIAL                # The initial parameter configuration from which
#                              the optimisation process will begin.
#-- mDEF                     # Model function that operates on the parameters to
#                              be optimized (K) and returns an observable
#                              object O.
#-- uDEF                     # Function that evaluates the performance of a
#                              given set of parameters K.
#-- rDEF                     # Function that defines a rule by which the
#                              parameters(K) are randomly altered.
#-- DATA = NULL              # A list that holds any supplementary data that
#                              functions mDEF or uDEF need to access.
#*******************************************************************************
################################################################################
#' @import foreach
#' @import iterators
#' @import parallel
#' @importFrom doParallel registerDoParallel
#' @importFrom grDevices dev.off pdf
#' @importFrom graphics lines par plot
#' @importFrom stats rbinom runif

OptimusSA <- function(NUMITER       = 1000000,
                      STATWINDOW    = 70,
                      T.INI         = 0.00001,
                      T.ADJSTEP     = 0.000000005,
                      TSCLnum       = 2,
                      T.SCALING     = 3,
                      T.MIN         = 0.000000005,
                      T.DELTA       = 2,
                      DUMP.FREQ     = 10000,
                      LIVEPLOT      = TRUE,
                      LIVEPLOT.FREQ = 100000,
                      PDFheight     = 29,
                      PDFwidth      = 20,
                      NCPU          = 4,
                      LONG          = TRUE,
                      SEED          = 840,
                      OPTNAME       = "",
                      CYCLES        = 10,
                      ACCRATIO.IN   = 90,
                      ACCRATIO.FIN  = 0.5,
                      DATA          = NULL,
                      K.INITIAL     = 0,
                      DIR,
                      rDEF,
                      mDEF,
                      uDEF,
                      starcore      = NULL
){
  ################################################################################
  
  # Reset graphical parameters to original values after function exit
  orig.par <- par(no.readonly=TRUE) 
  on.exit(par(orig.par))

  set.seed(SEED)

  suppressWarnings(requireNamespace("foreach"))
  suppressWarnings(requireNamespace("iterators"))
  suppressWarnings(requireNamespace("parallel"))
  if(NCPU > 1){
    suppressWarnings(requireNamespace("doParallel"))
    registerDoParallel(cores = NCPU)
    `%op%` <- `%dopar%`
    message(paste0("Running ", NCPU, " replicas of optimisation."))
  } else {
    `%op%` <- `%do%`
  }

  #-- Setting the seeds for the various replicas.
  seeds <- floor(runif(n=NCPU, min=1, max=1000))

  #-- INITIALISATION # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #-- The target energies of all the NUMITER trials.
  ENERGY.TRIAL.VEC      = NULL
  #-- The energy of the system, updated only if the move is accepted.
  ENERGY.DE.FACTO       = NULL
  #-- Probability of acceptance for each step.
  PROB.VEC              = NULL
  #-- Acceptance vector for each step: 1/0 = accept/don't accept.
  ACCEPTANCE            = NULL
  #-- The real temperature for each step.
  T.DE.FACTO            = NULL
  #-- The aimed ideal acceptance ratio.
  IDEAL.ACC.VEC         = rep(seq(from = ACCRATIO.IN, to = ACCRATIO.FIN, by =
                                    (ACCRATIO.FIN-ACCRATIO.IN)/((NUMITER/CYCLES)-1)
                                 ), CYCLES)
  #-- The calculated de facto acceptance rate over the last STATWINDOW.
  ACC.VEC.DE.FACTO      = NULL
  #-- The corresponding checkpoint steps.
  STEP4ACC.VEC.DE.FACTO = NULL
  #-- The quality of the prediction.
  Q.STRG                = NULL
  #-- The stored step.
  STEP.STORED           = NULL

  #-- initial big value, so that the first step will always be accepted!
  E.old         <- 100000
  #-- initial T for starting further adjustments
  T             <- T.INI
  #-- initial meaningless value!
  Q.old         <- 0
  #-- initial big value for the lowest energy model stored
  E.stored      <- 100000
  Step.stored   <- 1
  STEP.add      <- 1
  #-- initial K and O.
  K.stored      <- NULL
  O.stored      <- NULL
  # initial higtest order coef for starcore
  if (!is.null(starcore)) {
    Highest.order.coef.old <- 0
    N.TERMS               = NULL #-- number of terms
    COEF.ORDER            = NULL
  }
  #-- stores the definition of the temperature control unit
  #   to be evaluated in enviornment created by foreach
  tempControlDefinitionAsString <- tempControlDefinition()
  K <- K.INITIAL
  r <- rDEF
  m <- mDEF
  u <- uDEF
  #^^ INITIALISATION # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

  message("Monte Carlo optimisation with acceptance annealing...")


  #-- PARALLEL PROCESSING WRAP # # # # # # # # #
  suppressWarnings(foreach(repl=1:NCPU, .inorder=FALSE, .export = ls(environment())) %op% {

    e_new <- new.env()

    #temperature control unit definition
    eval(parse(text = tempControlDefinitionAsString))

    #initialize a temperature control unit
    tempControl <- get('tempControlUnit',e_new)$new(NumofAccRatSMIdeal = 0, NumofAccRatGRIdeal = 0, t.adjstep = T.ADJSTEP,
                                       T.ADJSTEP = T.ADJSTEP, AccR.category = "INITIAL", new.T.INI = T.INI,
                                       instanceOFswitch = 0, minT = T.MIN, max = TSCLnum, scaling = T.SCALING,
                                       DELTA = T.DELTA)
    rm(e_new)

    set.seed(seeds[repl])
    if(NCPU==1){ repl <- NULL }

    #-- STARTING MC ITERATIONS # # # # # # # # # # # # # # # # # # # # # # # # # #
    for(STEP in 1:NUMITER){  #-- step of the trial, from 1 to NUMITER

      if(STEP%%1000==0){
        message(paste0("Step ",STEP," out of ",NUMITER))
      }

      K.new <- r(K=K)
      if (is.null(DATA)) {
        O     <- m(K=K.new)
        snp   <- u(O=O)
      } else {
        O     <- m(K=K.new, DATA = DATA)
        snp   <- u(O=O, DATA = DATA)
      }


      Q       <- snp$Q
      E       <- snp$E                      ; ENERGY.TRIAL.VEC[STEP.add]<- E
      DE      <- E - E.old                  ; T.DE.FACTO[STEP.add]      <- T
      #-- Metropolis criterion
      P.accept<- min(1, exp(-DE/T))         ; PROB.VEC[STEP.add]        <- P.accept
      accept  <- rbinom(1, 1, prob=P.accept); ACCEPTANCE[STEP.add]      <- accept

      ################
      if( accept==1 ){

        E.old  <- E
        K      <- K.new
        Q.old  <- Q

        # For starcore, find highest.coef and evaluate.
        token <- TRUE
        if (!is.null(starcore)) {
          MAXCOEFORDER <- starcore['MAXCOEFORDER']
          N.terms.old  <- length(O$coefficients)
          highest.coef <- unlist(strsplit( format( max( abs(O$coefficients),na.rm=TRUE ), scientific=FALSE,trim=TRUE) ,"")) ##-- 16Jan13 --## removes sci notation and spaces for extremely large coefficients (the absence of this never caused a problem for backbone and methyls), now also abs() is added and NAs are removed while accounting the order of coefficients!
          dot.ind      <- which(highest.coef==".")
          if(length(dot.ind)!=0){ Highest.order.coef.old <- dot.ind-1 } else { Highest.order.coef.old <- length(highest.coef) }
          token <- (Highest.order.coef.old <= MAXCOEFORDER)
        }

        #-- # # # # # # # # #
        if(E.old < E.stored & token){
          E.stored       <- E.old
          Step.stored    <- STEP
          K.stored       <- K
          O.stored       <- O
          DUMP.MODEL     <- NULL
          DUMP.MODEL[1]  <- "QUALITY:"
          DUMP.MODEL[2]  <- paste0("E: ",round(E.old,3))
          DUMP.MODEL[3]  <- paste0("Q: ",round(Q.old,3))
          if (!is.null(starcore)) {
            DUMP.MODEL[4]  <- paste0("N of coef.: ",round(N.terms.old,3))
            DUMP.MODEL[5]  <- paste0("Order of largest coef.: ",Highest.order.coef.old)
            DUMP.MODEL[6]  <- "TERMS:"
            DUMP.MODEL[7]  <- paste(as.character(names(O$coefficients)), collapse=" ")
            DUMP.MODEL[8]  <- "COEFFICIENTS:"
            DUMP.MODEL[9]  <- paste(format(as.vector(O$coefficients), scientific=FALSE, trim=TRUE), collapse=" ") ##-- 16Jan --## removes sci notation, keeping NA
            DUMP.MODEL[10] <- "################################"
          }
          # DUMP.MODEL[4]  <- "TERMS:"
          # DUMP.MODEL[5]  <- paste(as.character(names(K.stored)), collapse=" ")
          # DUMP.MODEL[6]  <- "COEFFICIENTS:"
          # DUMP.MODEL[7]  <- paste(format(as.vector(K.stored), scientific=F, trim=T), collapse=" ")
          # DUMP.MODEL[8]  <- "OBSERVABLES:"
          # DUMP.MODEL[9]  <- paste(as.character(names(O.stored)), collapse=" ")
          # DUMP.MODEL[10] <- "PREDICTIONS:"
          # DUMP.MODEL[11] <- paste(format(as.vector(O.stored), scientific=F, trim=T), collapse=" ")
          # DUMP.MODEL[12] <- "TARGET:"
          # DUMP.MODEL[13] <- paste(format(as.vector(y), scientific=F, trim=T), collapse=" ")
          # DUMP.MODEL[14] <- "################################"
        }
        #-- # # # # # # # # #

      }
      ################

      ENERGY.DE.FACTO[STEP.add] <- E.old
      Q.STRG[STEP.add]          <- Q.old
      STEP.STORED[STEP.add]     <- STEP
      if (!is.null(starcore)) {
        COEF.ORDER[STEP.add]    <- Highest.order.coef.old
        N.TERMS[STEP.add]       <- N.terms.old
      }

      #-- Adjusting the temperature every STATWINDOW STEP
      if((STEP%%STATWINDOW) == 0){ #-- thus the number of entries is n*STATWINDOW
        #-- determine the new acceptance ratio
        accept.ratio.inlastWIN <- 100*sum(ACCEPTANCE[(length(ACCEPTANCE)-STATWINDOW+1):length(ACCEPTANCE)])/
          STATWINDOW
        ACC.VEC.DE.FACTO <- c(ACC.VEC.DE.FACTO, accept.ratio.inlastWIN)
        STEP4ACC.VEC.DE.FACTO <- c(STEP4ACC.VEC.DE.FACTO, STEP)

        #-- call the temperature control unit
        T <- tempControl$updateTemp(currentT = T, idealRatio = IDEAL.ACC.VEC[STEP], currentRatio = accept.ratio.inlastWIN)
      }

      #-- reseting temperature after a cycle is completed
      if(STEP%%(NUMITER/CYCLES)==0){
        #-- call the temperature control unit
        T <- tempControl$resetTemp()
      }
      #-- # # # # # # # # # # # # # # # # # # # # # # # #

      #-- PLOTTING  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
      if(LIVEPLOT==TRUE){
        if(STEP%%LIVEPLOT.FREQ == 0){

          pdf(width=PDFwidth, height=PDFheight, file=paste0(DIR,'/',OPTNAME,repl,".pdf"))
          par(mfrow=c(5,1))

          plot(y=PROB.VEC, x=STEP.STORED, ylab="Acceptance P", xlab="Step",
               ylim=c(0,1), xlim=range(STEP.STORED), type="l", col="blue", lwd=1)
          lines(y=c(0,1), x=rep(Step.stored,2), lwd="2.5", col="green")

          plot(y=T.DE.FACTO, x=STEP.STORED, ylab="Temperature", xlab="Step",
               xlim=range(STEP.STORED), type="l", col="orange", lwd=2)
          lines(y=range(T.DE.FACTO), x=rep(Step.stored,2), lwd="2.5", col="green")

          plot(y=IDEAL.ACC.VEC[STEP.STORED], x=STEP.STORED,
               ylab="Acceptance ratios (%)", xlab="Step", ylim=c(0,100),
               xlim=range(STEP.STORED), type="l",lty="dashed", lwd=2)
          lines(y=c(0,100), x=rep(Step.stored,2), lwd="2.5", col="green")
          if(length(ACC.VEC.DE.FACTO)!=0){
            lines(y=ACC.VEC.DE.FACTO, x=STEP4ACC.VEC.DE.FACTO, ylim=c(0,100),
                  xlim=range(STEP.STORED), col="red", lwd=2)
          }

          plot(y=ENERGY.DE.FACTO, x=STEP.STORED, ylab="Energy", xlab="Step",
               xlim=range(STEP.STORED), type="l", col="navy", lwd=2)
          lines(y=range(ENERGY.DE.FACTO), x=rep(Step.stored,2), lwd="2.5",
                col="green")

          plot(y=Q.STRG, x=STEP.STORED, ylab="Q", xlab="Step",
               xlim=range(STEP.STORED), type="l", col="blue", lwd=2)
          lines(y=range(Q.STRG), x=rep(Step.stored,2), lwd="2.5", col="green")

          if (!is.null(starcore)) {
            plot(y=N.TERMS, x=STEP.STORED, ylab="Number of Coefficients", xlab="Step", xlim=range(STEP.STORED), type="l", col="red", lwd=2)
            lines(y=range(N.TERMS), x=rep(Step.stored,2), lwd="2.5", col="green")
            plot(y=COEF.ORDER, x=STEP.STORED, ylab="Highest order of coef", xlab="Step", xlim=range(STEP.STORED), type="l", col="red", lwd=2)
            lines(y=range(COEF.ORDER), x=rep(Step.stored,2), lwd="2.5", col="green")
          }

          dev.off()

        }
      }
      #^^ PLOTTING  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #


      if( STEP%%DUMP.FREQ == 0 & exists("DUMP.MODEL") ){
        write(DUMP.MODEL, file=paste0(DIR,'/',OPTNAME,repl,"_model_QE.log"))
        save(K.stored,    file=paste0(DIR,'/',OPTNAME,repl,"_model_K.Rdata"))
        save(O.stored,    file=paste0(DIR,'/',OPTNAME,repl,"_model_O.Rdata"))
      }

      STEP.add <- STEP.add + 1    ########

      #-- Trimming the data holding vectors to be memory-friendly if LONG==TRUE
      if(LONG==TRUE){
        if(STEP%%10000 == 0 & STEP!=10000){
          ENERGY.DE.FACTO       <- ENERGY.DE.FACTO[(length(ENERGY.DE.FACTO)-10000+1):length(ENERGY.DE.FACTO)]
          Q.STRG                <- Q.STRG[(length(Q.STRG)-10000+1):length(Q.STRG)]
          STEP.STORED           <- STEP.STORED[(length(STEP.STORED)-10000+1):length(STEP.STORED)]
          ENERGY.TRIAL.VEC      <- ENERGY.TRIAL.VEC[(length(ENERGY.TRIAL.VEC)-10000+1):length(ENERGY.TRIAL.VEC)]
          T.DE.FACTO            <- T.DE.FACTO[(length(T.DE.FACTO)-10000+1):length(T.DE.FACTO)]
          PROB.VEC              <- PROB.VEC[(length(PROB.VEC)-10000+1):length(PROB.VEC)]
          ACCEPTANCE            <- ACCEPTANCE[(length(ACCEPTANCE)-10000+1):length(ACCEPTANCE)]
          ACC.VEC.DE.FACTO      <- ACC.VEC.DE.FACTO[(length(ACC.VEC.DE.FACTO)-(10000/STATWINDOW)+1):length(ACC.VEC.DE.FACTO)]
          STEP4ACC.VEC.DE.FACTO <- STEP4ACC.VEC.DE.FACTO[(length(STEP4ACC.VEC.DE.FACTO)-(10000/STATWINDOW)+1):length(STEP4ACC.VEC.DE.FACTO)]
          STEP.add              <- 10001
          if (!is.null(starcore)) {
            N.TERMS             <- N.TERMS[(length(N.TERMS)-10000+1):length(N.TERMS)]
            COEF.ORDER          <- COEF.ORDER[(length(COEF.ORDER)-10000+1):length(COEF.ORDER)]
          }

        }
      }
      #^^ # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    } ##-- for(STEP in 1:NUMITER)
    #^^ STARTING MC ITERATIONS # # # # # # # # # # # # # # # # # # # # # # # # # #

    #-- if LONG==TRUE, OUTPUT will only hold the trimmed data!
    OUTPUT                       <- NULL
    OUTPUT$K.stored              <- K.stored
    OUTPUT$O.stored              <- O.stored
    OUTPUT$STEP                  <- STEP
    OUTPUT$PROB.VEC              <- PROB.VEC
    OUTPUT$T.DE.FACTO            <- T.DE.FACTO
    OUTPUT$IDEAL.ACC.VEC         <- IDEAL.ACC.VEC
    OUTPUT$ACC.VEC.DE.FACTO      <- ACC.VEC.DE.FACTO
    OUTPUT$STEP4ACC.VEC.DE.FACTO <- STEP4ACC.VEC.DE.FACTO
    OUTPUT$ENERGY.DE.FACTO       <- ENERGY.DE.FACTO
    OUTPUT$Q.STRG                <- Q.STRG
    OUTPUT$ACCEPTANCE            <- ACCEPTANCE
    OUTPUT$STEP.STORED           <- STEP.STORED
    if (!is.null(starcore)) {
      OUTPUT$N.TERMS             <- N.TERMS
      OUTPUT$COEF.ORDER          <- COEF.ORDER
    }

    save(OUTPUT, file=paste0(DIR,'/',OPTNAME,repl,"_model_ALL.Rdata"))
  })
  #^^ PARALLEL PROCESSING WRAP # # # # # # # # #

  message("An optimal model is obtained and the data are saved !!!")
  if(NCPU==1){ return(OUTPUT) } else { return(0) }

}

################################################################################
