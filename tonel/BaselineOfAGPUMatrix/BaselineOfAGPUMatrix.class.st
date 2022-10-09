Class {
	#name : #BaselineOfAGPUMatrix,
	#superclass : #BaselineOf,
	#category : #BaselineOfAGPUMatrix
}

{ #category : #baselines }
BaselineOfAGPUMatrix >> baseline: spec [
    <baseline>
	spec 
		for: #common
		do: [ 
			spec baseline: 'AbstractGPU' with: [
				spec repository: 'github://ronsaldo/abstract-gpu' ].
		
			spec package: #'AbstractGPU-MatrixLibrary-Core' with: [ 
				spec requires: 'AbstractGPU' ]
		].

]
