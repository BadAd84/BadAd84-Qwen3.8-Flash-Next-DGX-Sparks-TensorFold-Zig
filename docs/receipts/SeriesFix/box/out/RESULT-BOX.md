# SeriesFix quick proof 2026-11-21T09:34:59+00:00

```
label	tag	head_piece	boot	repro	verdict	run1	run2	run3	server_line
s1536	s-1ece6e6d	1536	0	1	FAIL	FAIL
stream:
server:	FAIL
stream:
server:	FAIL
stream:
server:	error: cuMemsetD8Async: CUDA_ERROR_INVALID_VALUE (1) invalid argument
s768	s-1ece6e6d	768	0	0	PASS	PASS	PASS	PASS	 -
s256	s-1ece6e6d	256	0	0	PASS	PASS	PASS	PASS	 -
m-main	m-1ece6e6db	recipe	0	0	PASS	PASS	PASS	PASS	 -
```

recipe config.sh: 133:export TF_FLASHNEXT_HEAD_PIECE="${TF_FLASHNEXT_HEAD_PIECE:-1536}"
s1536 head-piece: TF_FLASHNEXT_HEAD_PIECE=1536 container: tensorfold-qwen38:s-1ece6e6d
s768 head-piece: TF_FLASHNEXT_HEAD_PIECE=768 container: tensorfold-qwen38:s-1ece6e6d
s256 head-piece: TF_FLASHNEXT_HEAD_PIECE=256 container: tensorfold-qwen38:s-1ece6e6d
m-main head-piece: TF_FLASHNEXT_HEAD_PIECE=1536 container: tensorfold-qwen38:m-1ece6e6db

prod after restore: absent
images: s-1ece6e6d sha256:c93a0286a454ece0e4e790ba273f1296912bfc2a1b5942291843bfe8621f5fe2 m-1ece6e6db sha256:323872ff61fea2623dbf0580705c1f7e1e3a3f0b3130f22fc6c5700974328c1e
