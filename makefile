.SECONDEXPANSION:
.PHONY: all gui download_moa clean plot_metrics pack_research .stream

ATTRIBUTES := 5
INSTANCES := 200000
SAMPLESIZE := 1000

PROJ_DIR := classifiers
MOAS_DIR := moa
RSCH_DIR := research
STRM_DIR := $(RSCH_DIR)/streams
EVAL_DIR := $(RSCH_DIR)/evaluations
PRED_DIR := $(RSCH_DIR)/predictions
PLOT_DIR := $(RSCH_DIR)/plots

MOA := moa-release-2017.06b

COMMA := ,
SPACE := $(eval) $(eval)

LEARNER-OOB := meta.OOB -s 15
LEARNER-UOB := meta.UOB -s 15
LEARNER-ESOS_ELM := ann.meta.ESOS_ELM -c (OS_ELM -i 100 -h 70 -p) -e (WELM -h 70 -p) -p 1000
LEARNER-OB := meta.OzaBag -s 15
LEARNER-VFDT := trees.HoeffdingTree

LEARNERS := $(patsubst LEARNER-%,%,$(filter LEARNER-%,$(.VARIABLES)))
STREAMS = $(shell grep -o -h -E '[^\/]+\.arff:$$' $(MAKEFILE_LIST) | tr '\n' ' ' | sed 's/\.arff://g')
CLASSPATH = $(shell cat .classpath)
JAVAAGENT = $(shell sed 's/:/\n/g' <<< $(CLASSPATH) | grep sizeofag)
JAVA = java -Ddtype=double -cp $(CLASSPATH) -javaagent:$(JAVAAGENT)
JAR := $(PROJ_DIR)/target/classifiers-1.0-SNAPSHOT.jar

all: $$(foreach stream_dir,$$(STREAMS),$$(foreach learner,$(LEARNERS),$(EVAL_DIR)/$$(stream_dir)/$$(learner).csv)) plot_metrics

gui: $(JAR) .classpath
	$(JAVA) moa.gui.GUI

plot_metrics:
	python scripts/plot_metrics.py -r -s 2 -a 20 $(EVAL_DIR) $(PLOT_DIR) 'G-Mean' 'Accuracy' 'Recall' 'Kappa' 'AUC' 'sAUC' 'Periodical holdout AUC' -o ESOS_ELM OOB UOB OB VFDT -d 70000 100000

pack_research:
	zipfile=$$(date '+%Y-%m-%d_%Hh%M')$(MSG); \
	zip $(RSCH_DIR)/$$zipfile $(wildcard *.streams); \
	cd $(RSCH_DIR); \
	zip -u -r $$zipfile $(patsubst $(RSCH_DIR)/%,%,$(STRM_DIR) $(EVAL_DIR) $(PRED_DIR) $(PLOT_DIR))

clean:
	rm -rf $(EVAL_DIR) $(STRM_DIR) $(PRED_DIR) $(PLOT_DIR)

$(JAR): $(shell find $(PROJ_DIR)/src/main/java) $(PROJ_DIR)/pom.xml
	cd $(PROJ_DIR) ;\
	mvn package

.classpath: $(PROJ_DIR)/pom.xml
	mvn -f $< dependency:resolve dependency:build-classpath -Dmdep.outputFile=../$@
	echo ':$(JAR)' >> $@

download_moa:
	mkdir -p $(MOAS_DIR)
	md5='4c304906dee7a5d6376c739b1b8c206f' ;\
	if [ -d $(MOAS_DIR)/$(MOA) ]; then echo '$(MOA) is already installed. Remove folder.'; exit; fi ;\
	if [ ! -f $(MOAS_DIR)/$(MOA).zip ]; then wget -P $(MOAS_DIR) http://downloads.sourceforge.net/sourceforge/moa-datastream/$(MOA).zip; fi ;\
	if [[ $$(md5sum $(MOAS_DIR)/$(MOA).zip | cut -d' ' -f1) != $$md5 ]]; then echo 'Wrong MD5 sum'; exit; fi ;\
	unzip $(MOAS_DIR)/$(MOA).zip -d $(MOAS_DIR) ;\
	find $(MOAS_DIR) -iname .ds_store -o -iname __macosx -o -iname $(MOA).zip | xargs rm -rf

$(EVAL_DIR)/%.csv: $(STRM_DIR)/$$(word 1,$$(subst /, ,%)).arff
	mkdir -p $(@D)
	mkdir -p $(patsubst $(EVAL_DIR)%,$(PRED_DIR)%,$(@D))
	time $(JAVA) moa.DoTask "EvaluatePrequential \
		-e (WindowAUCImbalancedPerformanceEvaluator -w $(SAMPLESIZE)) \
		-f $(SAMPLESIZE) \
		-s (ArffFileStream -f $<) \
		-l ($(LEARNER-$(*F))) \
		-o $(patsubst $(EVAL_DIR)%,$(PRED_DIR)%, $@)" \
		 > $@

.stream: $(JAR) .classpath
	mkdir -p $(STRM_DIR)
	$(JAVA) moa.DoTask 'WriteStreamToARFFFile -s ($(GENERATOR)) -f $(FILE) -m $(INSTANCES)'

include $(wildcard *.streams)
