library(MASS)
library(rmutil)
library(GA)
library(nplr)
library(lqmm)
library(numDeriv) 

Richards <- function(ti,pars) {
    den=(1+10^(pars[3]*(exp(pars[4])-ti)))^exp(pars[5])
    exp(pars[1])+(exp(pars[2]))/den
}     

mirrorRichards <- function(ti,pars) {
    peak <- exp(ifelse(ti<0,pars[4],pars[6]))
    symm <- exp(ifelse(ti<0,pars[5],pars[7]))
    hill <- ifelse(ti<0,pars[3],pars[8])
    den <- (1+10^(hill*((peak-abs(ti)))))^symm
    exp(pars[1])+exp(pars[2])/den
}

mirrorRichardsr <- function(ti,pars) {
    symm <- exp(pars[4])
    hill <- ifelse(ti<0,pars[3],pars[5])
    den <- (1+10^(-hill*ti))^symm
    exp(pars[1])+exp(pars[2])/den
}



growthGLM <- function(count,ti,timax=NA,family="Poisson",maxiter=1e4,runs=250,monotone=TRUE,weight=1) {

    if(is.na(timax)) {timax=max(ti)}
    if(!monotone) {
        timax=timax-ti[which.max(count)]
        ti=ti-ti[which.max(count)]}

    p2=log(max(count)-min(count))
    if(!monotone) {
        np=nplr(1:sum(ti<=0),convertToProp(count[which(ti<=0)]),useLog=F, silent = T)@pars}
    if(monotone) {
        np=nplr(ti,convertToProp(count),useLog=F, silent = T)@pars}
    np=as.vector(unlist(np))
    inits=c(log(min(count)+1),p2,np[4],log(np[3]),log(np[5]))
    if(any(is.nan(inits))){
        wnan <- which(is.nan(inits)) 
        inits[wnan] <- runif(length(wnan), 0, 5)
    }
    
    if(!monotone) {inits=c(inits,0,0,0)}
    
    if(family=="nb") {inits=c(inits,0)}

    if(monotone) {lp=Richards}
    if(!monotone) {lp=mirrorRichards}

    likPois=function(pars,ti,count) {
        linPred=lp(ti,pars)
        -sum(weight*dpois(count,linPred,log=T))
    }

    likNB=function(pars,ti,count) {
        linPred=lp(ti,pars)
        -sum(weight*dnbinom(count,size=exp(pars[length(pars)]),mu=linPred,log=T))
}

    if(family=="nb") {lik=likNB}
    if(family=="Poisson") {lik=likPois}
    if(family!="nb" & family!="Poisson") {stop("Family must be nb or Poisson")}
    
    inits2=optim(inits,function(x) lik(x,ti=ti,count=count),method="BFGS")$par
    
    rg=ga("real-valued",function(x) -lik(x,ti=ti,count=count),lower=rep(-20,length(inits)),upper=rep(20,length(inits)),maxiter=maxiter/2,run=runs,optim=TRUE,suggestions=rbind(inits,inits2))
    
    rg2=ga("real-valued",function(x) -lik(x,ti=ti,count=count),lower=rep(-20,length(inits)),upper=rep(20,length(inits)),maxiter=maxiter/2,optim=TRUE,run=runs)
    
    rg=ga("real-valued",function(x) -lik(x,ti=ti,count=count),lower=rep(-abs(min(rg@solution))*1.5,length(inits)),upper=rep(abs(max(rg@solution))*1.5,length(inits)),
          maxiter=maxiter,optim=TRUE,suggestions=rbind(rg@solution,rg2@solution),optimArgs=list(control=list(maxit=1000)),run=runs)

    pars=rg@solution[1,]

    hess=hessian(function(x) lik(x,ti=ti,count=count), pars)

    convergence=is.positive.definite(hess)
    if(!convergence) {hess=make.positive.definite(hess)}
    se=rep(NA,length(pars))
    if(!convergence) {warning("Information matrix is not positive definite, possible local optimum")}
    se=sqrt(diag(solve(hess)))
    ti=c(ti,(max(ti)+1):timax)
    
    linPred=lp(ti,pars)

    return(list(linPred=linPred,pars=pars,lik=rg@fitnessValue,R2=cor(count,linPred[1:length(count)])^2,se=se,hessian=hess,rg=rg))
}

growthGLMr <- function(count,ti,timax=NA,family="Poisson",maxiter=1e4,runs=500,monotone=TRUE,weight=1) {
    
    if(is.na(timax)) {timax=max(ti)}
    ti=ti/timax
    tinew=seq(0,1,length=timax)
    tiorig=ti
    if(!monotone) {
        tinew=(tinew-ti[which.max(count)[1]])
        ti=ti-ti[which.max(count)]
        ti[ti<0]=-(ti[ti<0]^2)
        ti[ti>0]=ti[ti>0]^2
        tinew[tinew<0]=-(tinew[tinew<0]^2)
        tinew[tinew>0]=(tinew[tinew>0]^2)
    }
    
    p2=log(max(count)-min(count))
    if(!monotone) {
        co=count[1:which.max(count)[1]]
        np=nplr(1:length(co),convertToProp(co),useLog=F,npars=5)@pars}
    if(monotone) {
        np=nplr(tiorig,convertToProp(count),useLog=F,npars=5)@pars}
    np=as.vector(unlist(np))
    inits=c(log(min(count)+1),p2,np[4],log(abs(np[3]+1e-12)),log(np[5]))
    if(!monotone) {inits[4]=inits[3]}
    
    if(family=="nb") {inits=c(inits,0)}
    
    if(monotone) {lp=Richards}
    if(!monotone) {lp=mirrorRichardsr}
    
    likPois=function(pars,ti,count) {
        linPred=lp(ti,pars)
        -sum(weight*dpois(count,linPred,log=T))
    }
    
    likNB=function(pars,ti,count) {
        linPred=lp(ti,pars)
        -sum(weight*dnbinom(count,size=exp(pars[length(pars)]),mu=linPred,log=T))
    }
    
    if(family=="nb") {lik=likNB}
    if(family=="Poisson") {lik=likPois}
    if(family!="nb" & family!="Poisson") {stop("Family must be nb or Poisson")}
    
    inits2=optim(inits,function(x) lik(x,ti=ti,count=count),method="BFGS")$par
    
    rg=ga("real-valued",function(x) -lik(x,ti=ti,count=count),lower=rep(-20,length(inits)),upper=rep(20,length(inits)),maxiter=maxiter/2,run=runs,optim=TRUE,suggestions=rbind(inits,inits2))
    
    rg2=ga("real-valued",function(x) -lik(x,ti=ti,count=count),lower=rep(-20,length(inits)),upper=rep(20,length(inits)),maxiter=maxiter/2,optim=TRUE,run=runs)
    
    rg=ga("real-valued",function(x) -lik(x,ti=ti,count=count),lower=rep(min(rg@solution)*1.5,length(inits)),upper=rep(max(rg@solution)*1.5,length(inits)),maxiter=maxiter,optim=TRUE,suggestions=rbind(rg@solution,rg2@solution),optimArgs=list(control=list(maxit=1000)),run=runs)
    
    pars=rg@solution[1,]
    
    hess=hessian(function(x) lik(x,ti=ti,count=count), pars)
    
    convergence=is.positive.definite(hess)
    if(!convergence) {hess=make.positive.definite(hess)}
    se=rep(NA,length(pars))
    if(!convergence) {warning("Information matrix is not positive definite, possible local optimum")}
    se=sqrt(diag(solve(hess)))
    
    linPred=lp(tinew,pars)
    
    return(list(linPred=linPred,pars=pars,lik=rg@fitnessValue,R2=cor(count,linPred[1:length(count)])^2,se=se,hessian=hess,rg=rg))
}


# growthGLMcov=function(count,ti,useCov=rep(0,5), cov.bottom=0,cov.top=0,cov.peak=0,cov.slope=0,cov.asy=0,gap.par=F,timax=NA,nstart=5000,useLog=F) {
#     
#     lti=ti
#     if(useLog) {lti=log10(ti)}
# 
#     if(is.na(timax)) {timax=max(ti)}
# 
#     p2=log(max(count)-min(count))
#     inits=c(min(count),p2,0.5,mean(lti),1)
#     
#     if(any(useCov==1)) {inits=c(inits,rep(0,sum(useCov)))}
#     if(gap.par) {inits=c(inits,0)}
#     
#     lik=function(pars,lti,count) {
#         if(length(pars<=5+sum(useCov))) {pars=c(pars,0)}
#         s=pars[5]+cov.asy*useCov[5]*pars[5+sum(useCov)]
#         la=pars[1]+cov.bottom*useCov[1]*pars[5+useCov[1]]
#         gap=pars[2]+cov.top*useCov[2]*pars[5+sum(useCov[1:2])]
#         hill=pars[3]+cov.slope*useCov[3]*pars[5+sum(useCov[1:3])]
#         peak=pars[4]+cov.peak*useCov[4]*pars[5+sum(useCov[1:4])]
#         tim=peak-lti
#         wm=which.min(abs(tim))
#         if(pars[5+sum(useCov)+1]!=0) {
#             pa=pars[5+sum(useCov)+1]
#             jnk=tim[abs(tim)<pa]
#             tim[abs(tim)<pa]=min(abs(tim))
#             tim[tim>=abs(pa)]=tim[tim>=abs(pa)]-max(jnk)
#             tim[tim<= -abs(pa)]=tim[tim<= -abs(pa)]-min(jnk)
#         }
#         den=(1+10^(hill*(tim)))^s
#         linPred=la+(exp(gap))/den
#         -sum(dpois(count,linPred,log=T))
#     }
# 
#     op=try(optim(inits,function(x) lik(x,lti=lti,count=count),method="BFGS",hessian=TRUE),silent=TRUE)
#     tries=0
#     while(inherits(op,"try-error") & tries<50) {
#     inits=inits+rnorm(length(inits))
#     op=try(optim(inits,function(x) lik(x,lti=lti,count=count),method="BFGS",hessian=TRUE),silent=TRUE)
#     tries=tries+1
#     }
#     if(tries==50) {stop("Something wrong here")}
#     if(nstart>1) {
#         for(repl in 2:nstart) {
#             inits=inits+rnorm(length(inits))
#             jnk=try(optim(inits,function(x) lik(x,lti=lti,count=count),method="BFGS",hessian=TRUE),silent=TRUE)
#             if(!inherits(jnk,"try-error") && jnk$value<op$value) {op=jnk}
#         }
# 
#     }
# 
#     
#     pars=op$par
#     if(length(pars<=5+sum(useCov))) {pars=c(pars,0)}
#         lti.add=(max(ti)+1):timax
#         if(useLog) {lti.add=log10(lti.add)}
#     lti=c(lti,lti.add)
#     if(useCov[5]) {cov.asy=c(cov.asy,rep(cov.asy[length(cov.asy)],length(lti.add)))}
#     if(useCov[1]) {cov.bottom=c(cov.bottom,rep(cov.bottom[length(cov.bottom)],length(lti.add)))}
#     if(useCov[2]) {cov.top=c(cov.top,rep(cov.top[length(cov.top)],length(lti.add)))}
#     if(useCov[3]) {cov.slope=c(cov.slope,rep(cov.slope[length(cov.slope)],length(lti.add)))}
#     if(useCov[4]) {cov.peak=c(cov.peak,rep(cov.peak[length(cov.peak)],length(lti.add)))}
# 
#     
#         s=pars[5]+cov.asy*useCov[5]*pars[5+sum(useCov)]
#         la=pars[1]+cov.bottom*useCov[1]*pars[5+useCov[1]]
#         gap=pars[2]+cov.top*useCov[2]*pars[5+sum(useCov[1:2])]
#         hill=pars[3]+cov.slope*useCov[3]*pars[5+sum(useCov[1:3])]
#         peak=pars[4]+cov.peak*useCov[4]*pars[5+sum(useCov[1:4])]
#         tim=peak-lti
#         wm=which.min(abs(tim))
#         if(pars[5+sum(useCov)+1]!=0) {
#             pa=pars[5+sum(useCov)+1]
#             jnk=tim[abs(tim)<pa]
#             tim[abs(tim)<pa]=min(abs(tim))
#             tim[tim>=abs(pa)]=tim[tim>=abs(pa)]-max(jnk)
#             tim[tim<= -abs(pa)]=tim[tim<= -abs(pa)]-min(jnk)
#         }
#         den=(1+10^(hill*(tim)))^s
#         linPred=la+(exp(gap))/den
# 
#     return(list(linPred=linPred,pars=pars,lik=-op$value,R2=cor(count,linPred[1:length(ti)])^2,
#                 peak=ifelse(useLog,10^peak,peak),se.unstransformed=sqrt(diag(solve(op$hessian))),op=op))
# }

