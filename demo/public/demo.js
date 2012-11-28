var timer = undefined;

function startInformationUpdater() {
    timer = setInterval(function () {
	updateInformations();
	updateProcessStatus();
    }, 2000);
};

function stopInformationUpdater() {
    clearInterval(timer);
};

function updateProcessStatus() {
    $.get("/process_status", function(status){
	switch (status) {
	case "nil":
	case "connection-failure":
	case "error":
	case "finished":
	    stopInformationUpdater();
	    setTimeout(updateInformations, 500);
	    break;
	}
    });
};

function updateProcessStatusMessage(msg) {
    $("#process-status-message").text(msg);
};

function updateTupleSpaceStatus(json) {
    $("#task-size").text(json.task);
    $("#working-size").text(json.working);
    $("#finished-size").text(json.finished);
    $("#data-size").text(json.data);
};

function updateTaskWorkerStatus(json) {
    $("#task-worker-status").empty();
    if (json.length == 0) {
	$("#task-worker-status").append($("<li>no task workers</li>"));
    } else {
	$("#task-worker-status").empty();
	jQuery.each(json, function(){
	    $("#task-worker-status").append($("<li/>").text(this));
	});
    }
};

function updateInputs(json) {
    $("#input-list").empty();
    if (json.length == 0) {
	$("#input-list").append($("<li>no inputs</li>"));
    } else {
	jQuery.each(json, function(){
	    $("#input-list").append($("<li/>").text(this));
	});
    }
};

function updateOutputs(json) {
    $("#output-list").empty();
    if (json.length == 0) {
	$("#output-list").append($("<li>no outputs</li>"));
    } else {
	jQuery.each(json, function(){
	    $("#output-list").append($("<li/>").text(this));
	});
    }
};

function updateInformations() {
    $.getJSON("/info", function(json){
	updateProcessStatusMessage(json.processStatusMessage);
	updateTupleSpaceStatus(json.tupleSpaceStatus);
	updateTaskWorkerStatus(json.taskWorkerStatus);
	updateInputs(json.inputs);
	updateOutputs(json.outputs);
    });
};

function requestProcess() {
    var document = $("#document").val();
    var parameters = $("#parameters").val();
    $.post("/process", {document: document, parameters: parameters}, function(){
	startInformationUpdater();
    });
};

function cleanProcess() {
    $.get("/clean", function() {
	setTimeout(updateInformations, 500);
    });
}

$(function(){
    updateInformations();
    $("#process-button").click(requestProcess);
    $("#clean-button").click(cleanProcess);
});
