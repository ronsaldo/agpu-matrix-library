"
Class:  
""I represent am the MVP matrix representation to be passed to the GPU.   
In the future I want to be a tensor"".

Responsibility:
I know how to multiply with another matrix.

Collaborators:
- AGPUMatMulXXXX - where XXX is FP32 or other value representation.

Instance creation:


Public API and Key Messages
- AGPUMatrix rows: 2 columns: 2 tabulate: [ :r :c |
		({{1. 2}.
		  {3. 4}} at: r) at: c ].
- @ - multiplies two matrices on GPU
- @! - multiplies two matrices on CPU for time comparison.
  
   One simple example is simply gorgeous.
 
Internal Representation and Key Implementation Points.
- Inherits from Array2D only because that was quickest MVP.  Highly likely to change in future.
"
Class {
	#name : #AGPUMatrix,
	#superclass : #Array2D,
	#pools : [
		'AGPUConstants'
	],
	#category : #'AbstractGPU-MatrixLibrary-Core'
}

{ #category : #operations }
AGPUMatrix >> @ rhs [
	
	^ AGPUMatMulFP32 uniqueInstance multiplyLeft: self byRight: rhs.
]

{ #category : #operations }
AGPUMatrix >> contentsAsFloatArray [
	contents := contents asFloatArray
]
